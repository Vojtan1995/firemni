import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../auth/auth_provider.dart';

/// Zda detail pochází z API nebo z lokální cache (offline detail).
enum SealDetailDataSource { online, offline }

/// Uloží detail ucpávky z API do Drift (sloupce + jsonPayload + metadata fotek).
Future<void> cacheSealDetailFromApi(AppDatabase db, Map<String, dynamic> seal) async {
  final id = seal['id'] as String;
  final existing = await (db.select(db.localSeals)..where((s) => s.id.equals(id))).getSingleOrNull();

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
          status: Value(seal['status'] as String? ?? 'draft'),
          version: Value(seal['version'] as int? ?? 1),
          isSynced: Value(existing?.isSynced == false ? false : true),
          syncConflict: Value(existing?.syncConflict ?? false),
          jsonPayload: Value(jsonEncode(seal)),
          updatedAt: DateTime.tryParse(seal['updatedAt'] as String? ?? '') ?? DateTime.now(),
        ),
      );

  for (final p in (seal['photos'] as List? ?? [])) {
    final m = p as Map<String, dynamic>;
    final photoId = m['id'] as String;
    final filePath = m['filePath'] as String;
    await db.into(db.localPhotos).insertOnConflictUpdate(
          LocalPhotosCompanion.insert(
            id: photoId,
            sealId: id,
            localPath: filePath,
            serverPath: Value(filePath),
            status: const Value('done'),
            createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
          ),
        );
  }
}

/// Sestaví mapu detailu pro UI z lokálního řádku a fotek (bez síťových volání).
Map<String, dynamic>? sealDetailFromLocal(LocalSeal row, List<LocalPhoto> photos) {
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
  seal['status'] = row.status;
  seal['version'] = row.version;

  final photoMaps = <Map<String, dynamic>>[];

  for (final p in photos) {
    final hasLocalFile = p.localPath.isNotEmpty && File(p.localPath).existsSync();
    if (hasLocalFile) {
      photoMaps.add({
        'id': p.id,
        'localPath': p.localPath,
        'filePath': p.serverPath,
      });
    } else if (p.serverPath != null && p.serverPath!.isNotEmpty) {
      photoMaps.add({
        'id': p.id,
        'filePath': p.serverPath,
        'localPath': p.localPath,
      });
    } else if (p.status == 'pending' && p.localPath.isNotEmpty) {
      photoMaps.add({
        'id': p.id,
        'localPath': p.localPath,
        'filePath': p.serverPath,
      });
    }
  }

  if (photoMaps.isNotEmpty) {
    seal['photos'] = photoMaps;
  }

  return seal;
}

class SealDetailScreen extends ConsumerStatefulWidget {
  const SealDetailScreen({super.key, required this.sealId});
  final String sealId;

  @override
  ConsumerState<SealDetailScreen> createState() => _SealDetailScreenState();
}

class _SealDetailScreenState extends ConsumerState<SealDetailScreen> {
  Map<String, dynamic>? _seal;
  bool _loading = true;
  bool _uploadingPhoto = false;
  SealDetailDataSource? _dataSource;
  String? _offlineHint;

  @override
  void initState() {
    super.initState();
    _load();
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
      if (!mounted) return;
      setState(() {
        _seal = seal;
        _dataSource = SealDetailDataSource.online;
        _loading = false;
      });
    } on DioException catch (_) {
      await _loadFromDrift(db);
    } catch (_) {
      await _loadFromDrift(db);
    }
  }

  Future<void> _loadFromDrift(AppDatabase db) async {
    final row = await (db.select(db.localSeals)..where((s) => s.id.equals(widget.sealId)))
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

    final photos = await (db.select(db.localPhotos)..where((p) => p.sealId.equals(widget.sealId))).get();
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
  }

  Future<void> _changeStatus(String status) async {
    if (_dataSource == SealDetailDataSource.offline) return;
    await ref.read(dioProvider).patch('/api/seals/${widget.sealId}/status', data: {'status': status});
    await _load();
  }

  Future<void> _pickPhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Vyfotit'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Vybrat z galerie'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _addPhotoFromSource(source);
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

      final dir = await getTemporaryDirectory();
      final out = '${dir.path}/${const Uuid().v4()}.webp';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        img.path,
        out,
        quality: 85,
        format: CompressFormat.webp,
      );
      if (compressed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Komprese fotky se nezdařila')),
          );
        }
        return;
      }

      final photoId = const Uuid().v4();
      final online = _dataSource == SealDetailDataSource.online;

      if (online) {
        try {
          final formData = FormData.fromMap({
            'photo': await MultipartFile.fromFile(compressed.path, filename: 'photo.webp'),
          });
          await ref.read(dioProvider).post('/api/seals/${widget.sealId}/photos', data: formData);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fotka nahrána')),
            );
          }
          await _load();
          return;
        } catch (_) {
          // fronta pro sync
        }
      }

      await db.into(db.localPhotos).insert(
            LocalPhotosCompanion.insert(
              id: photoId,
              sealId: widget.sealId,
              localPath: compressed.path,
              status: const Value('pending'),
              createdAt: DateTime.now(),
            ),
          );

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

  Widget _photoTile(Map<String, dynamic> m) {
    final localPath = m['localPath'] as String?;
    if (localPath != null && localPath.isNotEmpty && File(localPath).existsSync()) {
      return Image.file(File(localPath), height: 200, fit: BoxFit.cover);
    }

    final filePath = m['filePath'] as String?;
    if (_dataSource == SealDetailDataSource.online && filePath != null) {
      final url = '${AppConfig.apiBaseUrl}/uploads/$filePath';
      return Image.network(
        url,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 100),
      );
    }

    return Container(
      height: 120,
      color: Colors.grey.shade200,
      child: Center(
        child: Text(
          filePath != null ? 'Foto: $filePath\n(načtení vyžaduje síť)' : 'Lokální foto',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Ucpávka #${seal['sealNumber']}'),
        actions: [
          if (offline)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(Icons.cloud_off, size: 18),
                label: Text('Offline data'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (offline)
            MaterialBanner(
              content: Text(
                _offlineHint ??
                    'Zobrazena poslední uložená data z zařízení. Po připojení k serveru obnovte detail.',
              ),
              leading: const Icon(Icons.cloud_off),
              actions: [
                TextButton(onPressed: _load, child: const Text('Zkusit znovu')),
              ],
            ),
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: AppTheme.statusColor(status), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Systém: ${seal['system']}'),
          Text('Konstrukce: ${seal['construction']}'),
          Text('Umístění: ${seal['location']}'),
          Text('Odolnost: ${seal['fireRating']}'),
          if (seal['note'] != null) Text('Poznámka: ${seal['note']}'),
          const Divider(),
          const Text('Prostupy', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  : materials.map((x) => x is Map ? x['material'] : x.toString()).join(', ');
              return ListTile(
                title: Text('${m['entryType']} – ${m['dimension']}'),
                subtitle: Text('${m['quantity']} ks, ${m['insulation']}'),
                trailing: Text(matText),
              );
            }),
          const Divider(),
          const Text('Fotky', style: TextStyle(fontWeight: FontWeight.bold)),
          if (status == 'draft') ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _uploadingPhoto ? null : _pickPhotoSource,
              icon: _uploadingPhoto
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo),
              label: Text(_uploadingPhoto ? 'Nahrávám…' : 'Přidat fotku'),
            ),
          ],
          if ((seal['photos'] as List? ?? []).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Žádné fotky v cache.'),
            )
          else
            ...(seal['photos'] as List).map((p) {
              final m = p as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _photoTile(m),
              );
            }),
          if (auth.isManagement && !offline) ...[
            const SizedBox(height: 16),
            if (status == 'draft')
              ElevatedButton(onPressed: () => _changeStatus('checked'), child: const Text('Zkontrolovat')),
            if (status == 'checked') ...[
              ElevatedButton(onPressed: () => _changeStatus('invoiced'), child: const Text('Fakturovat')),
              OutlinedButton(onPressed: () => _changeStatus('draft'), child: const Text('Vrátit na rozpracováno')),
            ],
          ],
        ],
      ),
    );
  }
}
