import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../../widgets/app_top_actions.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../jobs/work_context_service.dart';
import '../sync/sync_retry.dart';
import '../sync/sync_service.dart';
import 'seal_photo_storage.dart';
import 'seal_photo_upload.dart';
import 'seal_calculations.dart';
import 'seal_note_helpers.dart';
import 'seal_status_actions.dart';
import 'seal_validation.dart';

/// Zda detail pochází z API nebo z lokální cache (offline detail).
enum SealDetailDataSource { online, offline }

double _num(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// Uloží metadata fotek z API do Drift (server ID, status done).
Future<void> cacheSealPhotosFromApiList(
  AppDatabase db,
  String sealId,
  List<dynamic>? photos,
) async {
  for (final p in (photos ?? [])) {
    final m = p as Map<String, dynamic>;
    final photoId = m['id'] as String;
    final filePath = m['filePath'] as String;
    final existing = await (db.select(db.localPhotos)
          ..where((row) => row.id.equals(photoId)))
        .getSingleOrNull();
    final keepLocalPath = existing != null &&
        existing.localPath.isNotEmpty &&
        File(existing.localPath).existsSync();

    await db.into(db.localPhotos).insertOnConflictUpdate(
          LocalPhotosCompanion.insert(
            id: photoId,
            sealId: sealId,
            localPath: keepLocalPath ? existing.localPath : '',
            serverPath: Value(filePath),
            status: const Value('done'),
            lastError: const Value(null),
            nextRetryAt: const Value(null),
            retryCount: const Value(0),
            createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
                existing?.createdAt ??
                DateTime.now(),
          ),
        );
  }
}

/// Uloží detail ucpávky z API do Drift (sloupce + jsonPayload + metadata fotek).
Future<void> cacheSealDetailFromApi(
    AppDatabase db, Map<String, dynamic> seal) async {
  final id = seal['id'] as String;
  final existing = await (db.select(db.localSeals)
        ..where((s) => s.id.equals(id)))
      .getSingleOrNull();

  await db.into(db.localSeals).insertOnConflictUpdate(
        LocalSealsCompanion.insert(
          id: id,
          jobId: seal['jobId'] as String,
          floorId: seal['floorId'] as String,
          sealNumber: seal['sealNumber'] as String,
          system: seal['system'] as String,
          construction: seal['construction'] as String,
          location: seal['location'] as String,
          fireRating: seal['fireRating'] as String,
          note: Value(seal['note'] as String?),
          internalNote: Value(seal['internalNote'] as String?),
          status: Value(seal['status'] as String? ?? 'draft'),
          version: Value(seal['version'] as int? ?? 1),
          isSynced: Value(existing?.isSynced == false ? false : true),
          syncConflict: Value(existing?.syncConflict ?? false),
          jsonPayload: Value(jsonEncode(seal)),
          updatedAt: DateTime.tryParse(seal['updatedAt'] as String? ?? '') ??
              DateTime.now(),
        ),
      );

  await cacheSealPhotosFromApiList(db, id, seal['photos'] as List?);

  if (seal['marker'] != null) {
    final marker = seal['marker'] as Map<String, dynamic>;
    await db.into(db.localSealMarkers).insertOnConflictUpdate(
          LocalSealMarkersCompanion.insert(
            sealId: id,
            floorId: marker['floorId'] as String? ?? seal['floorId'] as String,
            sealNumber: seal['sealNumber'] as String,
            x: (marker['x'] as num).toDouble(),
            y: (marker['y'] as num).toDouble(),
            updatedAt: DateTime.tryParse(marker['updatedAt'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
  }
}

/// Sestaví mapu detailu pro UI z lokálního řádku a fotek (bez síťových volání).
Map<String, dynamic>? sealDetailFromLocal(
    LocalSeal row, List<LocalPhoto> photos) {
  Map<String, dynamic> seal;
  if (row.jsonPayload != null && row.jsonPayload!.isNotEmpty) {
    seal = Map<String, dynamic>.from(jsonDecode(row.jsonPayload!) as Map);
  } else {
    seal = {
      'entries': <dynamic>[],
      'photos': <dynamic>[],
    };
  }

  seal['id'] = row.id;
  seal['jobId'] = row.jobId;
  seal['floorId'] = row.floorId;
  seal['sealNumber'] = row.sealNumber;
  seal['system'] = row.system;
  seal['construction'] = row.construction;
  seal['location'] = row.location;
  seal['fireRating'] = row.fireRating;
  seal['note'] = row.note;
  seal['internalNote'] = row.internalNote;
  seal['status'] = row.status;
  seal['version'] = row.version;

  final photoMaps = <Map<String, dynamic>>[];

  for (final p in photos) {
    final map = {
      'id': p.id,
      'localPath': p.localPath,
      'filePath': p.serverPath,
      'status': p.status,
      if (p.lastError != null) 'lastError': p.lastError,
    };

    final hasLocalFile =
        p.localPath.isNotEmpty && File(p.localPath).existsSync();
    if (hasLocalFile) {
      photoMaps.add(map);
    } else if (p.serverPath != null && p.serverPath!.isNotEmpty) {
      photoMaps.add(map);
    } else if ((p.status == 'pending' || p.status == 'failed') &&
        p.localPath.isNotEmpty) {
      photoMaps.add(map);
    }
  }

  if (photoMaps.isNotEmpty) {
    seal['photos'] = photoMaps;
  }

  return seal;
}

/// Sloučí fotky z API s lokálními pending/failed řádky a statusy.
List<Map<String, dynamic>> mergePhotosForDisplay(
  List<dynamic>? apiPhotos,
  List<LocalPhoto> localPhotos,
) {
  final result = <Map<String, dynamic>>[];
  final localById = {for (final p in localPhotos) p.id: p};
  final seen = <String>{};

  for (final p in (apiPhotos ?? [])) {
    final m = Map<String, dynamic>.from(p as Map);
    final id = m['id'] as String;
    seen.add(id);
    final local = localById[id];
    if (local != null) {
      // Photo returned by API is on the server — do not show stale failed overlay.
      m['status'] = 'done';
      if (local.localPath.isNotEmpty && File(local.localPath).existsSync()) {
        m['localPath'] = local.localPath;
      }
    } else {
      m['status'] = 'done';
    }
    result.add(m);
  }

  for (final p in localPhotos) {
    if (seen.contains(p.id)) continue;
    if (p.status != 'pending' && p.status != 'failed') continue;
    result.add({
      'id': p.id,
      'localPath': p.localPath,
      'filePath': p.serverPath,
      'status': p.status,
      if (p.lastError != null) 'lastError': p.lastError,
    });
  }

  return result;
}

class SealDetailScreen extends ConsumerStatefulWidget {
  const SealDetailScreen({super.key, required this.sealId});
  final String sealId;

  @override
  ConsumerState<SealDetailScreen> createState() => _SealDetailScreenState();
}

class _SealDetailScreenState extends ConsumerState<SealDetailScreen> {
  Map<String, dynamic>? _seal;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _uploadingPhoto = false;
  SealDetailDataSource? _dataSource;
  String? _offlineHint;
  final Map<String, Uint8List> _photoBytesCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _persistSealContext(Map<String, dynamic> seal) async {
    final userId = ref.read(currentUserIdProvider);
    final jobId = seal['jobId'] as String?;
    final floorId = seal['floorId'] as String?;
    if (userId == null || jobId == null || floorId == null) return;
    await WorkContextService(ref.read(databaseProvider)).saveSeal(
      userId: userId,
      jobId: jobId,
      floorId: floorId,
      sealId: widget.sealId,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offlineHint = null;
    });

    final db = ref.read(databaseProvider);
    final dio = ref.read(dioProvider);

    try {
      final res = await dio.get('/api/seals/${widget.sealId}');
      final seal = Map<String, dynamic>.from(res.data as Map);
      await cacheSealDetailFromApi(db, seal);
      final localPhotos = await (db.select(db.localPhotos)
            ..where((p) => p.sealId.equals(widget.sealId)))
          .get();
      seal['photos'] = mergePhotosForDisplay(
        seal['photos'] as List?,
        localPhotos,
      );
      if (!mounted) return;
      setState(() {
        _seal = seal;
        _dataSource = SealDetailDataSource.online;
        _loading = false;
      });
      await _persistSealContext(seal);
      await _loadHistory();
    } on DioException catch (_) {
      await _loadFromDrift(db);
    } catch (_) {
      await _loadFromDrift(db);
    }
  }

  Future<void> _loadFromDrift(AppDatabase db) async {
    final row = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(widget.sealId)))
        .getSingleOrNull();

    if (row == null) {
      if (!mounted) return;
      setState(() {
        _seal = null;
        _dataSource = SealDetailDataSource.offline;
        _offlineHint =
            'Server nedostupný a detail této ucpávky není v lokální cache. Nejprve otevřete ucpávku při připojení k síti.';
        _loading = false;
      });
      return;
    }

    final photos = await (db.select(db.localPhotos)
          ..where((p) => p.sealId.equals(widget.sealId)))
        .get();
    final seal = sealDetailFromLocal(row, photos);
    final hasDetail = row.jsonPayload != null && row.jsonPayload!.isNotEmpty;

    if (!mounted) return;
    setState(() {
      _seal = seal;
      _dataSource = SealDetailDataSource.offline;
      _offlineHint = hasDetail
          ? null
          : 'V cache je jen základ údajů; prostupy a fotky z API zde nejsou. Po připojení obnovte detail.';
      _loading = false;
    });
    if (seal != null) {
      await _persistSealContext(seal);
    }
  }

  Future<void> _reviewSeal(String action) async {
    String? comment;
    if (action == 'returned') {
      final ctrl = TextEditingController();
      comment = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vrátit k opravě'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Komentář (povinný)'),
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Potvrdit'),
            ),
          ],
        ),
      );
      if (comment == null || comment.isEmpty) return;
    }
    try {
      await ref.read(dioProvider).patch('/api/seals/${widget.sealId}/review', data: {
        'action': action,
        if (comment != null) 'comment': comment,
      });
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Revize selhala')),
      );
    }
  }

  Future<void> _changeStatus(String status) async {
    if (_dataSource == SealDetailDataSource.offline) return;
    if (status == 'checked' && _seal != null) {
      final issues = validateSealForChecked(_seal!);
      if (issues.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ucpávka není kompletní'),
            content: SingleChildScrollView(
              child: Text(formatSealValidationIssues(issues)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        return;
      }
    }
    String? comment;
    if (status == 'draft') {
      comment = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('Vrátit k opravě'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Komentář (povinný)'),
              maxLines: 3,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Potvrdit'),
              ),
            ],
          );
        },
      );
      if (comment == null || comment.isEmpty) return;
    }
    try {
      await ref.read(dioProvider).patch('/api/seals/${widget.sealId}/status', data: {
        'status': status,
        if (comment != null) 'comment': comment,
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stav ucpávky byl aktualizován')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Změna stavu selhala')),
      );
    }
  }

  Future<void> _approveSeal() async {
    if (_dataSource == SealDetailDataSource.offline) return;
    if (_seal != null) {
      final issues = validateSealForChecked(_seal!);
      if (issues.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ucpávka není kompletní'),
            content: SingleChildScrollView(
              child: Text(formatSealValidationIssues(issues)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        return;
      }
    }
    final status = _seal?['status'] as String? ?? 'draft';
    if (status == 'draft') {
      await _changeStatus('checked');
      return;
    }
    await _reviewSeal('approved');
  }

  Future<void> _loadHistory() async {
    final auth = ref.read(authServiceProvider);
    if (!auth.canViewSealHistory) return;
    try {
      final res = await ref.read(dioProvider).get('/api/seals/${widget.sealId}/history');
      if (!mounted) return;
      setState(() {
        _history = (res.data as List).cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatHistoryEntry(Map<String, dynamic> h) {
    const fieldLabels = {
      'status': 'Stav',
      'note': 'Poznámka',
      'internalNote': 'Interní poznámka',
      'entries': 'Prostupy',
      'photos': 'Fotografie',
      'system': 'Systém',
    };
    final field = h['fieldName'] as String?;
    final oldV = h['oldValue'];
    final newV = h['newValue'];
    final action = h['action'] as String?;
    if (field != null) {
      final label = fieldLabels[field] ?? field;
      if (oldV == null || oldV == '') return '$label: $newV';
      return '$label: $oldV → $newV';
    }
    switch (action) {
      case 'photo_upload':
        return 'Přidána fotografie';
      case 'create':
        return 'Vytvoření ucpávky';
      case 'status_change':
        return 'Změna stavu';
      default:
        return action ?? 'Akce';
    }
  }

  Future<void> _addPhotoFromSource(ImageSource source) async {
    if (_uploadingPhoto) return;
    setState(() => _uploadingPhoto = true);
    final db = ref.read(databaseProvider);

    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: source, imageQuality: 85);
      if (img == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fotka nebyla vybrána')),
          );
        }
        return;
      }

      final persistedPath = await compressAndPersistSealPhoto(img.path);
      if (persistedPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Komprese fotky se nezdařila')),
          );
        }
        return;
      }

      final photoId = const Uuid().v4();
      final online = _dataSource == SealDetailDataSource.online;

      await db.into(db.localPhotos).insert(
            LocalPhotosCompanion.insert(
              id: photoId,
              sealId: widget.sealId,
              localPath: persistedPath,
              status: const Value('pending'),
              createdAt: DateTime.now(),
            ),
          );

      if (online) {
        PreparedPhotoUpload? prepared;
        try {
          final upload = await sealPhotoMultipartFile(persistedPath);
          prepared = upload.prepared;
          final formData = FormData.fromMap({
            'photo': upload.multipart,
            'photoType': 'detail',
          });
          final res = await ref
              .read(dioProvider)
              .post('/api/seals/${widget.sealId}/photos', data: formData);
          final data = res.data is Map ? res.data as Map : const {};
          await markPhotoSyncSuccess(
            db,
            photoId,
            serverPath: data['filePath'] as String?,
            serverPhotoId: data['id'] as String?,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fotka nahrána')),
            );
          }
          await _load();
          return;
        } catch (_) {
          // fronta pro sync — pending řádek zůstává
        } finally {
          await prepared?.dispose();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              online
                  ? 'Fotka uložena lokálně, odešle se při synchronizaci'
                  : 'Fotka uložena lokálně, odešle se po připojení',
            ),
          ),
        );
      }
      await _loadFromDrift(db);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotku se nepodařilo přidat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _retryPhotoUpload(String photoId) async {
    final db = ref.read(databaseProvider);
    await resetPhotoForRetry(db, photoId);
    await ref.read(syncServiceProvider).syncAll(force: true);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opakovaný upload fotky dokončen')),
    );
  }

  String _photoStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'Čeká na upload';
      case 'failed':
        return 'Selhala';
      case 'done':
        return 'Nahraná';
      default:
        return status ?? '';
    }
  }

  Color _photoStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'failed':
        return AppColors.error;
      case 'done':
        return AppColors.success;
      default:
        return AppColors.textMuted;
    }
  }

  Widget _photoTile(Map<String, dynamic> m, int index, List<Map<String, dynamic>> allPhotos) {
    final status = m['status'] as String?;
    final lastError = m['lastError'] as String?;

    Widget image;
    final localPath = m['localPath'] as String?;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      image = Image.file(File(localPath), height: 200, fit: BoxFit.cover);
    } else {
      final id = m['id'] as String?;
      if (_dataSource == SealDetailDataSource.online && id != null) {
        final photoId = id;
        image = FutureBuilder<Response<List<int>>>(
          future: ref.read(dioProvider).get<List<int>>(
                '/api/photos/$photoId/file',
                options: Options(responseType: ResponseType.bytes),
              ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Container(
                height: 200,
                color: AppColors.bgSecondary,
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            final bytes = snapshot.data?.data;
            if (snapshot.hasError || bytes == null || bytes.isEmpty) {
              return const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image, size: 100)),
              );
            }
            _photoBytesCache[photoId] = Uint8List.fromList(bytes);
            return Image.memory(Uint8List.fromList(bytes),
                height: 200, fit: BoxFit.cover);
          },
        );
      } else {
        final filePath = m['filePath'] as String?;
        image = Container(
          height: 120,
          color: AppColors.bgSecondary,
          child: Center(
            child: Text(
              filePath != null
                  ? 'Foto: $filePath\n(načtení vyžaduje síť)'
                  : 'Lokální foto',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _openPhotoGallery(index, allPhotos),
          child: ClipRRect(
            borderRadius: AppRadius.mdAll,
            child: image,
          ),
        ),
        if (status != null && status.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: _photoStatusColor(status)),
              const SizedBox(width: 6),
              Text(
                _photoStatusLabel(status),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _photoStatusColor(status),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          if (status == 'failed' && lastError != null && lastError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                lastError,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
              ),
            ),
          if (status == 'failed')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _uploadingPhoto
                    ? null
                    : () => _retryPhotoUpload(m['id'] as String),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Zkusit znovu'),
              ),
            ),
        ],
      ],
    );
  }

  Future<ImageProvider?> _photoProviderFor(Map<String, dynamic> m) async {
    final localPath = m['localPath'] as String?;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      return FileImage(File(localPath));
    }
    final id = m['id'] as String?;
    if (id != null && _photoBytesCache.containsKey(id)) {
      return MemoryImage(_photoBytesCache[id]!);
    }
    if (_dataSource == SealDetailDataSource.online && id != null) {
      try {
        final res = await ref.read(dioProvider).get<List<int>>(
              '/api/photos/$id/file',
              options: Options(responseType: ResponseType.bytes),
            );
        final bytes = res.data;
        if (bytes != null && bytes.isNotEmpty) {
          _photoBytesCache[id] = Uint8List.fromList(bytes);
          return MemoryImage(_photoBytesCache[id]!);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _openPhotoGallery(
    int initialIndex,
    List<Map<String, dynamic>> photos,
  ) async {
    if (photos.isEmpty) return;

    final providers = <ImageProvider>[];
    final indexMap = <int, int>{};

    for (var i = 0; i < photos.length; i++) {
      final provider = await _photoProviderFor(photos[i]);
      if (provider != null) {
        indexMap[i] = providers.length;
        providers.add(provider);
      }
    }

    if (providers.isEmpty || !mounted) return;

    final galleryIndex = indexMap[initialIndex] ?? 0;
    await showPhotoFullscreen(
      context,
      image: providers[galleryIndex],
      gallery: providers,
      initialIndex: galleryIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_seal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail ucpávky')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _offlineHint ?? 'Ucpávka nenalezena.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final seal = _seal!;
    final status = seal['status'] as String;
    final auth = ref.read(authServiceProvider);
    final offline = _dataSource == SealDetailDataSource.offline;

    final floorId = seal['floorId'] as String?;
    final jobId = seal['jobId'] as String?;
    final marker = seal['marker'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ucpávka #${seal['sealNumber']}'),
        actions: [
          const AppTopActions(),
          if (offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(label: 'Offline data', compact: true)),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (floorId != null && jobId != null && jobId.isNotEmpty)
            AppSecondaryButton(
              label: 'Otevřít ve výkresu',
              icon: Icons.map_outlined,
              onPressed: () {
                final params = marker != null
                    ? 'jobId=$jobId&focusSealId=${widget.sealId}'
                    : 'jobId=$jobId&placeSealId=${widget.sealId}';
                context.push('/floor-plan/$floorId?$params');
              },
            ),
          if (offline)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: AppColors.warning, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _offlineHint ??
                          'Zobrazena poslastní uložená data z zařízení. Po připojení k serveru obnovte detail.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.warning,
                          ),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Zkusit znovu')),
                ],
              ),
            ),
          StatusBadge(status: status),
          const SizedBox(height: AppSpacing.lg),
          Text('Systém: ${seal['system']}'),
          Text('Konstrukce: ${seal['construction']}'),
          Text('Umístění: ${seal['location']}'),
          Text('Odolnost: ${seal['fireRating']}'),
          if (seal['openingLengthMm'] != null && seal['openingWidthMm'] != null)
            Text(
              'Rozměr prostupu: ${seal['openingLengthMm']} × ${seal['openingWidthMm']} mm',
            ),
          if (SealNoteHelpers.showPublicNoteInDetail(auth.role) &&
              seal['note'] != null &&
              (seal['note'] as String).trim().isNotEmpty)
            _SealNoteBlock(label: 'Poznámka', text: seal['note'] as String),
          if (SealNoteHelpers.showInternalNoteInDetail(auth.role) &&
              seal['internalNote'] != null &&
              (seal['internalNote'] as String).trim().isNotEmpty)
            _SealNoteBlock(
              label: auth.isWorker ? 'Interní poznámka' : 'Interní poznámka z terénu',
              text: seal['internalNote'] as String,
            ),
          if (auth.isVedeni || auth.isAdmin || auth.isUcetni) ...[
            const Divider(height: 24),
            const Text('Evidence', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Vytvořil: ${(seal['createdBy'] as Map?)?['displayName'] ?? '—'}',
            ),
            Text('Datum vytvoření: ${_formatDate(seal['createdAt'] as String?)}'),
            Text(
              'Poslední editor: ${(seal['updatedBy'] as Map?)?['displayName'] ?? '—'}',
            ),
            Text('Poslední editace: ${_formatDate(seal['updatedAt'] as String?)}'),
          ],
          if (status == 'invoiced') ...[
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock, size: 18, color: AppColors.warning),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Uzamčeno — fakturováno')),
                ],
              ),
            ),
          ],
          if (status == 'draft' || status == 'checked') ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final jobId = seal['jobId'] as String? ?? '';
                final floorId = seal['floorId'] as String? ?? '';
                context.push(
                  '/seal/${widget.sealId}/edit?jobId=$jobId&floorId=$floorId',
                );
              },
              icon: const Icon(Icons.edit),
              label: Text(status == 'checked'
                  ? 'Upravit (vrátí na rozpracováno)'
                  : 'Upravit ucpávku'),
            ),
          ],
          const SectionHeader(title: 'Prostupy', style: SectionHeaderStyle.h3),
          if ((seal['entries'] as List? ?? []).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Žádné prostupy v cache.'),
            )
          else
            ...(seal['entries'] as List).map((e) {
              final m = e as Map<String, dynamic>;
              final materials = m['materials'] as List?;
              final matText = materials == null
                  ? ''
                  : materials
                      .map((x) => x is Map ? x['material'] : x.toString())
                      .join(', ');
              final unitPrice = m['unitPrice'];
              final totalPrice = m['totalPrice'];
              final priceVersion = m['priceListVersion'] as String?;
              final unit = (m['unit'] as String?) ?? 'kus';
              final qty = m['quantity'];
              final qtyNum = qty is num
                  ? qty.toDouble()
                  : double.tryParse(qty?.toString() ?? '') ?? 1;
              final hasPrice = unitPrice != null && totalPrice != null;
              String formatCzk(dynamic value) {
                if (value == null) return '—';
                final n = value is num
                    ? value.toDouble()
                    : double.tryParse(value.toString());
                if (n == null) return '—';
                return '${n.toStringAsFixed(0)} Kč';
              }

              String qtyDisplay() {
                if (unit == 'm2') return '${formatArea(qtyNum)} ${unitLabel(unit)}';
                if (unit == 'mb') return '${formatMb(qtyNum)} ${unitLabel(unit)}';
                return '${qtyNum.round()} ${unitLabel(unit)}';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${m['entryType']} – ${m['dimension']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('${qtyDisplay()}, ${m['insulation']}'),
                      if (matText.isNotEmpty) Text('Materiály: $matText'),
                      if (m['calculatedAreaM2'] != null)
                        Text(
                          'Plocha: ${formatArea(_num(m['calculatedAreaM2']))} m²',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (m['calculatedNetAreaM2'] != null)
                        Text(
                          'Čistá plocha: ${formatArea(_num(m['calculatedNetAreaM2']))} m²',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (m['calculatedLinearMeters'] != null)
                        Text(
                          'Běžné metry: ${formatMb(_num(m['calculatedLinearMeters']))} mb',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 8),
                      if (hasPrice) ...[
                        Text('Cena celkem: ${formatCzk(totalPrice)}'),
                        if (qtyNum > 1 || unit != 'kus')
                          Text(
                            'Jednotková cena: ${formatCzk(unitPrice)} / ${unitLabel(unit)}',
                          )
                        else
                          Text('Jednotková cena: ${formatCzk(unitPrice)}'),
                        if (priceVersion != null && priceVersion.isNotEmpty)
                          Text(
                            'Ceník: $priceVersion',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ] else
                        Chip(
                          label: const Text('Bez ceny'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ),
              );
            }),
          const SectionHeader(title: 'Fotky', style: SectionHeaderStyle.h3),
          if (status == 'draft') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadingPhoto
                        ? null
                        : () => _addPhotoFromSource(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Vyfotit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadingPhoto
                        ? null
                        : () => _addPhotoFromSource(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galerie'),
                  ),
                ),
              ],
            ),
            if (_uploadingPhoto)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
          if ((seal['photos'] as List? ?? []).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Žádné fotky v cache.'),
            )
          else
            ...(seal['photos'] as List).toList().asMap().entries.map((entry) {
              final m = entry.value as Map<String, dynamic>;
              final allPhotos = (seal['photos'] as List)
                  .cast<Map<String, dynamic>>();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _photoTile(m, entry.key, allPhotos),
              );
            }),
          if (auth.canViewSealHistory && _history.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Historie změn', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._history.map((h) {
              final editor = h['editor'] as Map<String, dynamic>?;
              final ts = h['timestamp'] as String?;
              final desc = _formatHistoryEntry(h);
              return ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 18),
                title: Text(desc, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '${_formatDate(ts)} · ${editor?['displayName'] ?? ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }),
          ],
          if (seal['reviewComment'] != null &&
              (seal['reviewComment'] as String).trim().isNotEmpty)
            _SealNoteBlock(
              label: 'Poznámka k revizi',
              text: seal['reviewComment'] as String,
            ),
          SealStatusActions(
            auth: auth,
            status: status,
            reviewStatus: seal['reviewStatus'] as String?,
            offline: offline,
            onApprove: _approveSeal,
            onReturnForRepair: () => _reviewSeal('returned'),
            onInvoice: () => _changeStatus('invoiced'),
            onRevertToDraft: () => _changeStatus('draft'),
          ),
        ],
      ),
    );
  }
}

class _SealNoteBlock extends StatelessWidget {
  const _SealNoteBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
