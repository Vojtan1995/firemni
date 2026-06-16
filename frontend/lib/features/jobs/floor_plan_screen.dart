import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import 'dart:convert';
import '../reports/export_service.dart' show ExportSaveCancelled;
import '../sync/sync_service.dart';
import 'floor_drawing_storage.dart';
import 'floor_plan/floor_drawing_download_service.dart';
import 'floor_plan/floor_drawing_service.dart';
import 'floor_plan/floor_drawing_status.dart';
import 'floor_plan/floor_drawing_upload.dart';
import 'floor_plan/floor_plan_viewer.dart';
import 'floor_plan/floor_plan_filter_sheet.dart';
import 'floor_plan/floor_plan_filters.dart';
import 'floor_plan/marker_colors.dart';
import 'floor_plan/placement_stats_banner.dart';
import 'job_context_bar.dart';

/// Výsledek potvrzení umístění značky ve draft režimu formuláře.
class SealPlacementResult {
  const SealPlacementResult({required this.x, required this.y});
  final double x;
  final double y;
}

class FloorPlanScreen extends ConsumerStatefulWidget {
  const FloorPlanScreen({
    super.key,
    required this.jobId,
    required this.floorId,
    this.placeSealId,
    this.focusSealId,
    this.draftPlacement = false,
    this.draftSealNumber,
  });

  final String jobId;
  final String floorId;
  final String? placeSealId;
  final String? focusSealId;
  final bool draftPlacement;
  final String? draftSealNumber;

  @override
  ConsumerState<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends ConsumerState<FloorPlanScreen> {
  final _transformController = TransformationController();

  Map<String, dynamic>? _drawing;
  List<Map<String, dynamic>> _markers = [];
  List<Map<String, dynamic>> _floorSeals = [];
  Uint8List? _imageBytes;
  bool _loading = true;
  String? _error;
  String? _placingSealId;
  String? _movingSealId;
  double? _pendingX;
  double? _pendingY;
  double? _draftX;
  double? _draftY;
  bool _draftDirty = false;
  bool _fromCache = false;
  bool _uploading = false;
  String? _offlinePendingMessage;
  FloorPlanFilterState _filter = const FloorPlanFilterState();
  String? _highlightSealId;
  int _total = 0;
  int _placed = 0;
  int _unplaced = 0;
  double _viewerScale = 1;
  Size? _canvasSize;

  @override
  void initState() {
    super.initState();
    _placingSealId = widget.placeSealId;
    _highlightSealId = widget.focusSealId;
    _transformController.addListener(_onTransformChanged);
    _load();
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if ((scale - _viewerScale).abs() > 0.05 && mounted) {
      setState(() => _viewerScale = scale);
    }
  }

  bool get _isDraftMode => widget.draftPlacement;

  /// True pokud je podkladem rastrový obrázek (ne PDF) s nízkým rozlišením,
  /// kde přiblížení bude rozmazané — zobrazí varovný banner.
  bool get _isLowResRaster {
    if (_loading || _imageBytes == null) return false;
    final mime = (_drawing?['mimeType'] as String?)?.toLowerCase() ?? '';
    if (mime.contains('pdf')) return false;
    final width = (_drawing?['width'] as int?) ?? 0;
    return width > 0 && width < 2500;
  }

  List<Map<String, dynamic>> get _displayMarkers {
    if (!_isDraftMode || _draftX == null || _draftY == null) {
      return _visibleMarkers;
    }
    return [
      ..._visibleMarkers,
      {
        'sealId': '__draft__',
        'sealNumber': widget.draftSealNumber ?? '?',
        'x': _draftX,
        'y': _draftY,
        'status': 'draft',
      },
    ];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
      _offlinePendingMessage = null;
    });
    final db = ref.read(databaseProvider);
    await _loadFloorSeals(db);
    final hadCache = await _loadOffline(db, keepLoading: true);
    if (hadCache && mounted) {
      setState(() {
        _loading = false;
        _fromCache = true;
      });
    }
    try {
      final res = await ref.read(dioProvider).get(
        '/api/jobs/${widget.jobId}/floors/${widget.floorId}/drawing',
      );
      final data = res.data as Map<String, dynamic>;
      final drawing = data['drawing'] as Map<String, dynamic>?;
      final markers =
          (data['markers'] as List? ?? []).cast<Map<String, dynamic>>();
      await _cacheBundle(db, drawing, markers);
      Uint8List? bytes;
      if (drawing != null) {
        bytes = await _fetchDrawingBytes(drawing['fileUrl'] as String?);
        if (bytes != null) {
          final mime = drawing['mimeType'] as String? ?? 'image/webp';
          final ext = floorDrawingExtensionForMime(mime);
          final localPath = await persistFloorDrawingBytes(
            widget.floorId,
            bytes,
            extension: ext,
          );
          await db.into(db.localFloorDrawings).insertOnConflictUpdate(
                LocalFloorDrawingsCompanion.insert(
                  floorId: widget.floorId,
                  jobId: widget.jobId,
                  filePath: drawing['filePath'] as String,
                  localPath: Value(localPath),
                  mimeType: mime,
                  width: drawing['width'] as int? ?? 1,
                  height: drawing['height'] as int? ?? 1,
                  downloadStatus: Value(
                    FloorDrawingDownloadStatus.downloaded.toDb(),
                  ),
                  updatedAt: DateTime.tryParse(
                          drawing['updatedAt'] as String? ?? '') ??
                      DateTime.now(),
                ),
              );
        }
      }
      await _loadFloorSealsFromApi();
      _mergeCreatorFromMarkers(markers);
      await _loadPlacementStats();
      if (!mounted) return;
      setState(() {
        _drawing = drawing;
        _markers = _enrichMarkers(markers);
        _imageBytes = bytes;
        _loading = false;
        _fromCache = false;
      });
      _focusSealIfNeeded();
    } on DioException catch (_) {
      if (!hadCache) {
        await _loadOffline(db);
      }
      await _loadPlacementStats(offline: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadFloorSeals(AppDatabase db) async {
    final rows = await (db.select(db.localSeals)
          ..where((s) =>
              s.floorId.equals(widget.floorId) & s.deletedAt.isNull()))
        .get();
    _floorSeals = rows.map((r) {
      String? createdById;
      String? createdByName;
      String? reviewStatus;
      if (r.jsonPayload != null && r.jsonPayload!.isNotEmpty) {
        final payload = jsonDecode(r.jsonPayload!) as Map<String, dynamic>;
        createdById = payload['createdById'] as String?;
        createdByName = payload['createdByName'] as String?;
        reviewStatus = payload['reviewStatus'] as String?;
      }
      return {
        'id': r.id,
        'sealNumber': r.sealNumber,
        'status': r.status,
        'reviewStatus': reviewStatus,
        'createdById': createdById,
        'createdByName': createdByName,
      };
    }).toList();
  }

  void _mergeCreatorFromMarkers(List<Map<String, dynamic>> markers) {
    final bySealId = {for (final m in markers) m['sealId'] as String: m};
    _floorSeals = _floorSeals.map((s) {
      final m = bySealId[s['id'] as String];
      if (m == null) return s;
      return {
        ...s,
        'createdById': s['createdById'] ?? m['createdById'],
        'createdByName': s['createdByName'] ?? m['createdByName'],
        'reviewStatus': s['reviewStatus'] ?? m['reviewStatus'],
        'status': m['status'] ?? s['status'],
      };
    }).toList();
  }

  Future<void> _loadFloorSealsFromApi() async {
    try {
      final res = await ref.read(dioProvider).get(
        '/api/seals/floors/${widget.floorId}/seals',
      );
      final apiList = (res.data as List).cast<Map<String, dynamic>>();
      final byId = {for (final s in _floorSeals) s['id'] as String: s};
      _floorSeals = apiList.map((m) {
        final id = m['id'] as String;
        final existing = byId[id];
        final worker = m['worker'] as Map<String, dynamic>?;
        final createdById = worker?['id'] as String? ??
            existing?['createdById'] as String?;
        final createdByName = worker?['displayName'] as String? ??
            worker?['username'] as String? ??
            existing?['createdByName'] as String?;
        return {
          'id': id,
          'sealNumber': m['sealNumber'] as String,
          'status': m['status'] as String? ?? existing?['status'] ?? 'draft',
          'reviewStatus':
              m['reviewStatus'] as String? ?? existing?['reviewStatus'],
          'createdById': createdById,
          'createdByName': createdByName,
        };
      }).toList();
    } catch (_) {}
  }

  Future<void> _loadPlacementStats({bool offline = false}) async {
    if (!offline) {
      try {
        final res = await ref.read(dioProvider).get(
          '/api/jobs/${widget.jobId}/floors/${widget.floorId}/placement-stats',
        );
        final data = res.data as Map<String, dynamic>;
        _total = data['total'] as int? ?? 0;
        _placed = data['placed'] as int? ?? 0;
        _unplaced = data['unplaced'] as int? ?? 0;
        return;
      } catch (_) {}
    }
    final placedIds = _markers.map((m) => m['sealId'] as String).toSet();
    _total = _floorSeals.length;
    _placed = _floorSeals.where((s) => placedIds.contains(s['id'])).length;
    _unplaced = _total - _placed;
  }

  void _focusSealIfNeeded() {
    final id = _highlightSealId ?? widget.focusSealId;
    if (id == null) return;
    final marker = _markers.cast<Map<String, dynamic>?>().firstWhere(
          (m) => m?['sealId'] == id,
          orElse: () => null,
        );
    if (marker == null) return;
    final canvas = _canvasSize;
    if (canvas == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSealIfNeeded();
      });
      return;
    }
    final x = (marker['x'] as num).toDouble();
    final y = (marker['y'] as num).toDouble();
    _transformController.value = focusTransformForMarker(
      x: x,
      y: y,
      canvasSize: canvas,
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightSealId = null);
    });
  }

  List<Map<String, dynamic>> _enrichMarkers(List<Map<String, dynamic>> markers) {
    final sealMeta = {for (final s in _floorSeals) s['id'] as String: s};
    return markers
        .map((m) {
          final sealId = m['sealId'] as String;
          final meta = sealMeta[sealId];
          return {
            ...m,
            'createdById': m['createdById'] ?? meta?['createdById'],
            'createdByName': m['createdByName'] ?? meta?['createdByName'],
          };
        })
        .toList();
  }

  Future<void> _cacheBundle(
    AppDatabase db,
    Map<String, dynamic>? drawing,
    List<Map<String, dynamic>> markers,
  ) async {
    if (drawing != null) {
      await upsertFloorDrawingMetadata(
        db,
        floorId: widget.floorId,
        jobId: widget.jobId,
        meta: drawing,
      );
    }
    for (final m in markers) {
      await db.into(db.localSealMarkers).insertOnConflictUpdate(
            LocalSealMarkersCompanion.insert(
              sealId: m['sealId'] as String,
              floorId: widget.floorId,
              sealNumber: m['sealNumber'] as String? ?? '',
              x: (m['x'] as num).toDouble(),
              y: (m['y'] as num).toDouble(),
              updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                  DateTime.now(),
            ),
          );
    }
  }

  Future<Uint8List?> _fetchDrawingBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    final res = await ref.read(dioProvider).get(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
    final data = res.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  Future<bool> _loadOffline(AppDatabase db, {bool keepLoading = false}) async {
    final drawingRow = await (db.select(db.localFloorDrawings)
          ..where((d) => d.floorId.equals(widget.floorId)))
        .getSingleOrNull();
    final markerRows = await (db.select(db.localSealMarkers)
          ..where((m) => m.floorId.equals(widget.floorId)))
        .get();
    await _loadFloorSeals(db);
    Uint8List? bytes;
    if (drawingRow?.localPath != null &&
        File(drawingRow!.localPath!).existsSync()) {
      bytes = await File(drawingRow.localPath!).readAsBytes();
    }
    final sealById = {for (final s in _floorSeals) s['id'] as String: s};
    final hasCache = bytes != null && bytes.isNotEmpty;
    final hasMetadata = drawingRow != null && drawingRow.filePath.isNotEmpty;
    if (!mounted) return hasCache;
    setState(() {
      _drawing = drawingRow == null
          ? null
          : {
              'width': drawingRow.width,
              'height': drawingRow.height,
              'mimeType': drawingRow.mimeType,
            };
      _markers = markerRows
          // Přeskočit osiřelé markery (ucpávka smazaná/neexistuje), aby
          // na výkrese nezůstala fantomová značka.
          .where((m) => sealById.containsKey(m.sealId))
          .map((m) {
            final seal = sealById[m.sealId];
            return {
              'sealId': m.sealId,
              'sealNumber': m.sealNumber,
              'x': m.x,
              'y': m.y,
              'status': seal?['status'] ?? 'draft',
              'reviewStatus': seal?['reviewStatus'],
            };
          })
          .toList();
      _imageBytes = bytes;
      if (!keepLoading) _loading = false;
      _fromCache = hasCache;
      _offlinePendingMessage = hasMetadata && !hasCache
          ? 'Výkres existuje, soubor není stažen. Připojte síť nebo počkejte na stažení.'
          : null;
      _error = !hasCache && !hasMetadata
          ? 'Výkres není v offline cache'
          : null;
    });
    _focusSealIfNeeded();
    return hasCache;
  }

  Future<void> _uploadDrawing() async {
    final replacing = _drawing != null;
    setState(() => _uploading = true);
    try {
      final uploaded = await pickAndUploadFloorDrawing(
        context: context,
        dio: ref.read(dioProvider),
        jobId: widget.jobId,
        floorId: widget.floorId,
      );
      if (!uploaded) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(replacing ? 'Výkres nahrazen' : 'Výkres nahrán'),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Upload selhal'))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDrawing() async {
    try {
      final deleted = await confirmAndDeleteFloorDrawing(
        context: context,
        dio: ref.read(dioProvider),
        jobId: widget.jobId,
        floorId: widget.floorId,
      );
      if (!deleted) return;
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Smazání selhalo'))),
      );
    }
  }

  Future<void> _saveMarker(String sealId, double x, double y) async {
    final db = ref.read(databaseProvider);
    final sealRow = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(sealId)))
        .getSingleOrNull();
    final sealNumber = sealRow?.sealNumber ??
        _markers.firstWhere(
          (m) => m['sealId'] == sealId,
          orElse: () => {'sealNumber': ''},
        )['sealNumber'] as String;

    await db.into(db.localSealMarkers).insertOnConflictUpdate(
          LocalSealMarkersCompanion.insert(
            sealId: sealId,
            floorId: widget.floorId,
            sealNumber: sealNumber,
            x: x,
            y: y,
            updatedAt: DateTime.now(),
          ),
        );

    await (db.update(db.localSeals)..where((s) => s.id.equals(sealId))).write(
          const LocalSealsCompanion(
            markerPlacementPending: Value(false),
          ),
        );

    await ref.read(syncServiceProvider).enqueueMutation(
          db: db,
          entityType: 'seal_marker',
          operation: 'update',
          payload: {
            'sealId': sealId,
            'floorId': widget.floorId,
            'x': x,
            'y': y,
          },
        );

    try {
      await ref.read(dioProvider).put(
        '/api/jobs/${widget.jobId}/floors/${widget.floorId}/markers/$sealId',
        data: {'x': x, 'y': y},
      );
      await ref.read(syncServiceProvider).syncAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pozice značky uložena')),
        );
      }
      setState(() {
        _placingSealId = null;
        _movingSealId = null;
        _pendingX = null;
        _pendingY = null;
      });
      await _load();
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() {
        _placingSealId = null;
        _movingSealId = null;
        _pendingX = null;
        _pendingY = null;
        final idx = _markers.indexWhere((m) => m['sealId'] == sealId);
        final entry = {
          'sealId': sealId,
          'sealNumber': sealNumber,
          'x': x,
          'y': y,
          'status': sealRow?.status ?? 'draft',
        };
        if (idx >= 0) {
          _markers[idx] = entry;
        } else {
          _markers.add(entry);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Značka uložena lokálně — synchronizuje se po připojení'),
        ),
      );
    }
  }

  Future<bool> _confirmLeaveDraft() async {
    if (!_isDraftMode || !_draftDirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neuložené umístění'),
        content: const Text(
          'Změny pozice značky nebudou potvrzeny. Opravdu odejít?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zůstat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Odejít'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  void _confirmDraftPlacement() {
    if (_draftX == null || _draftY == null) return;
    final result = SealPlacementResult(x: _draftX!, y: _draftY!);
    _popRoute(result);
  }

  /// Pop route after draft guard allows it (avoids PopScope + canPop:false crash).
  void _popRoute([Object? result]) {
    if (_isDraftMode && _draftDirty) {
      setState(() => _draftDirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop(result);
      });
      return;
    }
    context.pop(result);
  }

  bool get _draftBlocksPop => _isDraftMode && _draftDirty;

  Future<void> _onTapPlan(Offset local, Size size) async {
    if (size.width <= 0 || size.height <= 0) return;
    final normalized = tapToNormalizedMarker(local, size);
    final x = normalized.dx;
    final y = normalized.dy;

    if (_isDraftMode) {
      setState(() {
        _draftX = x;
        _draftY = y;
        _draftDirty = true;
      });
      return;
    }

    if (_placingSealId != null || _movingSealId != null) {
      // Klepnutí jen označí cílovou pozici; uloží se až tlačítkem „Uložit"
      // ve spodní liště — méně rušivé než potvrzovací dialog.
      setState(() {
        _pendingX = x;
        _pendingY = y;
      });
    }
  }

  /// Uloží rozpracované umístění/přesun značky (tlačítko „Uložit" ve spodní liště).
  Future<void> _savePendingPlacement() async {
    final sealId = _placingSealId ?? _movingSealId;
    if (sealId == null || _pendingX == null || _pendingY == null) return;
    await _saveMarker(sealId, _pendingX!, _pendingY!);
  }

  void _cancelPlacement() {
    setState(() {
      _placingSealId = null;
      _movingSealId = null;
      _pendingX = null;
      _pendingY = null;
    });
  }

  bool _canMoveMarker(Map<String, dynamic> marker) {
    final auth = ref.read(authServiceProvider);
    if (auth.isUcetni) return false;
    if (auth.isVedeni || auth.isAdmin) return true;
    final userId = ref.read(currentUserIdProvider);
    return marker['createdById'] == userId ||
        _floorSeals.any((s) =>
            s['id'] == marker['sealId'] && s['createdById'] == userId);
  }

  Future<void> _onMarkerTap(Map<String, dynamic> marker) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('Ucpávka #${marker['sealNumber']}'),
              subtitle: Text(markerStatusLabel(
                status: marker['status'] as String? ?? 'draft',
                reviewStatus: marker['reviewStatus'] as String?,
              )),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Detail ucpávky'),
              onTap: () => Navigator.pop(ctx, 'detail'),
            ),
            if (_canMoveMarker(marker))
              ListTile(
                leading: const Icon(Icons.open_with),
                title: const Text('Přesunout'),
                onTap: () => Navigator.pop(ctx, 'move'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'detail') {
      context.push('/seal/${marker['sealId']}');
    } else if (action == 'move') {
      setState(() => _movingSealId = marker['sealId'] as String);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Klepněte na nové místo a potvrďte uložení')),
      );
    }
  }

  Future<void> _showFindSeal() async {
    final placedIds = _markers.map((m) => m['sealId'] as String).toSet();
    final ctrl = TextEditingController();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Najít ucpávku'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Číslo ucpávky'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Nebo vyberte ze seznamu'),
              items: _floorSeals
                  .map((s) => DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text('#${s['sealNumber']}'),
                      ))
                  .toList(),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
          FilledButton(
            onPressed: () {
              final num = ctrl.text.trim();
              final seal = _floorSeals.cast<Map<String, dynamic>?>().firstWhere(
                    (s) => s?['sealNumber'] == num,
                    orElse: () => null,
                  );
              Navigator.pop(ctx, seal?['id'] as String?);
            },
            child: const Text('Najít'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    if (!placedIds.contains(selected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tato ucpávka zatím není umístěna ve výkresu.'),
        ),
      );
      return;
    }
    setState(() => _highlightSealId = selected);
    _focusSealIfNeeded();
  }

  Future<void> _showUnplaced() async {
    final placedIds = _markers.map((m) => m['sealId'] as String).toSet();
    final userId = ref.read(currentUserIdProvider);
    final unplaced = _floorSeals.where((s) {
      if (placedIds.contains(s['id'])) return false;
      return _filter.matchesUnplacedSeal(
        {...s, 'createdById': s['createdById']},
        userId,
      );
    }).toList();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Neumístěné ucpávky',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (unplaced.isEmpty)
              const ListTile(title: Text('Všechny ucpávky jsou umístěny')),
            ...unplaced.map((s) => ListTile(
                  title: Text('#${s['sealNumber']}'),
                  trailing: const Icon(Icons.place_outlined),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(
                      '/floor-plan/${widget.floorId}?jobId=${widget.jobId}&placeSealId=${s['id']}',
                    );
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    if (!ref.read(authServiceProvider).canAccessReports) return;
    try {
      await exportFloorDrawingPdf(
        dio: ref.read(dioProvider),
        jobId: widget.jobId,
        floorId: widget.floorId,
        fileNameBase: 'vykres-${widget.floorId}',
        filter: _filter,
        currentUserId: ref.read(currentUserIdProvider),
      );
    } on FloorDrawingExportUnsupported {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Export neumístěných ucpávek na výkresu není k dispozici',
          ),
        ),
      );
    } on ExportSaveCancelled {
      // user dismissed save dialog
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Export selhal'))),
      );
    }
  }

  Future<void> _showFilters() async {
    final auth = ref.read(authServiceProvider);
    final result = await FloorPlanFilterSheet.show(
      context,
      initial: _filter,
      floorSeals: _floorSeals,
      hideByWorker: auth.isWorker,
      currentUserId: ref.read(currentUserIdProvider),
    );
    if (result != null) setState(() => _filter = result);
  }

  List<Map<String, dynamic>> get _visibleMarkers {
    final userId = ref.read(currentUserIdProvider);
    final placedIds = _markers.map((m) => m['sealId'] as String).toSet();
    if (_filter.mode == FloorPlanMarkerFilter.unplacedOnly) return [];
    return _markers.where((m) {
      return _filter.matchesMarker(
        marker: m,
        placedSealIds: placedIds,
        currentUserId: userId,
        createdById: m['createdById'] as String?,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    final width = (_drawing?['width'] as int?) ?? 1;
    final height = (_drawing?['height'] as int?) ?? 1;

    return PopScope(
      canPop: !_draftBlocksPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_draftBlocksPop) return;
        if (await _confirmLeaveDraft()) {
          _popRoute();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isDraftMode ? 'Umístit značku' : 'Výkres patra'),
        actions: [
          if (_imageBytes != null) ...[
            if (auth.canAccessReports)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Export PDF',
                onPressed: _exportPdf,
              ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Najít ucpávku',
              onPressed: _showFindSeal,
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtry',
              onPressed: _showFilters,
            ),
          ],
          if (auth.canManageFloorDrawings) ...[
            IconButton(
              icon: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              onPressed: _uploading ? null : _uploadDrawing,
              tooltip: _drawing != null ? 'Nahradit výkres' : 'Nahrát výkres',
            ),
            if (_drawing != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteDrawing,
                tooltip: 'Smazat výkres',
              ),
          ],
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                JobContextBar(jobId: widget.jobId),
                PlacementStatsBanner(
                  total: _total,
                  placed: _placed,
                  unplaced: _unplaced,
                  onShowUnplaced: _unplaced > 0 ? _showUnplaced : null,
                ),
                if (_filter.isActive)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filtr: ${_filter.description}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Zrušit filtr',
                          onPressed: () => setState(
                            () => _filter = FloorPlanFilterState.allFilters,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_fromCache && !_loading)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    color: AppColors.warning.withValues(alpha: 0.12),
                    child: Text(
                      'Offline — zobrazena uložená cache výkresu',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_isLowResRaster)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    color: AppColors.warning.withValues(alpha: 0.12),
                    child: Text(
                      'Výkres má nízké rozlišení a při přiblížení může být rozmazaný.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_isDraftMode || _placingSealId != null || _movingSealId != null)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    color: AppColors.info.withValues(alpha: 0.15),
                    child: Text(
                      _isDraftMode
                          ? 'Klepněte na výkres a potvrďte umístění tlačítkem dole'
                          : _placingSealId != null
                              ? 'Klepněte na výkres a uložte značku tlačítkem dole'
                              : 'Klepněte na nové místo a uložte přesun tlačítkem dole',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ),
                Expanded(
                  child: _imageBytes == null
                      ? EmptyState(
                          message: _offlinePendingMessage ??
                              (auth.canManageFloorDrawings
                                  ? 'Patro nemá výkres — nahrajte obrázek nebo PDF'
                                  : 'Výkres zatím není nahrán'),
                          icon: _offlinePendingMessage != null
                              ? Icons.cloud_download_outlined
                              : Icons.map_outlined,
                          action: _offlinePendingMessage != null
                              ? null
                              : auth.canManageFloorDrawings
                                  ? AppPrimaryButton(
                                      label: 'Nahrát výkres',
                                      fullWidth: false,
                                      onPressed:
                                          _uploading ? null : _uploadDrawing,
                                    )
                                  : null,
                        )
                      : FloorPlanViewer(
                          bytes: _imageBytes!,
                          mimeType:
                              _drawing?['mimeType'] as String? ?? 'image/webp',
                          intrinsicWidth: width,
                          intrinsicHeight: height,
                          transformationController: _transformController,
                          viewerScale: _viewerScale,
                          markers: _displayMarkers,
                          highlightSealId: _highlightSealId,
                          onCanvasSizeChanged: (size) {
                            if (_canvasSize != size) {
                              setState(() => _canvasSize = size);
                            }
                          },
                          onTapPlan: (_isDraftMode ||
                                  _placingSealId != null ||
                                  _movingSealId != null)
                              ? _onTapPlan
                              : null,
                          onMarkerTap: _onMarkerTap,
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    ),
    );
  }

  /// Spodní akční lišta: výrazné tlačítko Uložit pro umístění/přesun značky,
  /// případně potvrzení umístění v draft režimu formuláře.
  Widget? _buildBottomBar() {
    if (_isDraftMode) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: FilledButton(
            onPressed:
                _draftX != null && _draftY != null ? _confirmDraftPlacement : null,
            child: const Text('Potvrdit umístění'),
          ),
        ),
      );
    }
    if (_placingSealId != null || _movingSealId != null) {
      final canSave = _pendingX != null && _pendingY != null;
      final label = _placingSealId != null ? 'Uložit značku' : 'Uložit pozici';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelPlacement,
                  child: const Text('Zrušit'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: canSave ? _savePendingPlacement : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(label),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return null;
  }
}
