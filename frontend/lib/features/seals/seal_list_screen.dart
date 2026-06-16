import 'dart:convert';

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
import '../../widgets/app_top_actions.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../jobs/floor_plan/floor_drawing_service.dart';
import '../jobs/job_context_bar.dart';
import '../jobs/work_context_service.dart';
import '../reports/export_service.dart';
import '../sync/sync_conflict.dart';
import 'seal_bulk_actions.dart';
import 'seal_list_filters.dart';
import 'seal_list_helpers.dart';
import 'seal_list_row.dart';

/// Zda seznam pochází z API nebo z lokální cache (FE-01).
enum SealListDataSource { online, offline }

class SealListScreen extends ConsumerStatefulWidget {
  const SealListScreen({super.key, required this.floorId, required this.jobId});
  final String floorId;
  final String jobId;

  @override
  ConsumerState<SealListScreen> createState() => _SealListScreenState();
}

class _SealListScreenState extends ConsumerState<SealListScreen> {
  List<Map<String, dynamic>> _seals = [];
  Set<String> _conflictSealIds = {};
  bool _loading = true;
  SealListDataSource? _dataSource;
  Set<String> _selectedIds = {};
  String? _floorName;
  String? _offlineHint;
  final Set<SealProblemFilter> _activeFilters = {};
  bool? _hasDrawing;
  bool _uploadingDrawing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isWorker => ref.read(authServiceProvider).isWorker;

  Future<void> _persistFloorContext({String? floorName}) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null || widget.jobId.isEmpty) return;
    await WorkContextService(ref.read(databaseProvider)).saveFloor(
      userId: userId,
      jobId: widget.jobId,
      floorId: widget.floorId,
      floorName: floorName ?? _floorName,
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
      final apiFilters = sealFiltersToApi(_activeFilters);
      final res = await dio.get(
        '/api/seals/floors/${widget.floorId}/seals',
        queryParameters:
            apiFilters.isEmpty ? null : {'filters': apiFilters.join(',')},
      );
      final apiList = (res.data as List).cast<Map<String, dynamic>>();
      try {
        final floors = await dio.get('/api/jobs/${widget.jobId}/floors');
        final floorList = (floors.data as List).cast<Map<String, dynamic>>();
        _floorName = floorList
            .cast<Map<String, dynamic>?>()
            .firstWhere((f) => f?['id'] == widget.floorId, orElse: () => null)?['name'] as String?;
      } catch (_) {}
      await _cacheSealsFromApi(db, apiList);
      final merged = await _mergeWithUnsyncedLocal(db, apiList);
      await _enrichWithLocalSyncFlags(db, merged);
      final conflictIds = await _loadConflictSealIds(db, merged);
      await _persistFloorContext();
      await _enrichWithMarkerPlacement(db, merged);
      final hasDrawing = await _loadDrawingAvailability(dio, db);
      if (!mounted) return;
      setState(() {
        _seals = _applyActiveFilters(merged);
        _conflictSealIds = conflictIds;
        _hasDrawing = hasDrawing;
        _dataSource = SealListDataSource.online;
        _loading = false;
      });
    } on DioException catch (_) {
      await _loadFromDrift(db);
    } catch (_) {
      await _loadFromDrift(db);
    }
  }

  Future<void> _cacheSealsFromApi(
      AppDatabase db, List<Map<String, dynamic>> apiList) async {
    final userId = ref.read(currentUserIdProvider);
    for (final m in apiList) {
      final id = m['id'] as String;
      final existing = await (db.select(db.localSeals)
            ..where((s) => s.id.equals(id)))
          .getSingleOrNull();
      final syncFlags = await sealListCacheSyncFlags(
        db,
        sealId: id,
        existing: existing,
        userId: userId,
      );

      final reviewStatus = m['reviewStatus'] as String?;
      String? jsonPayload = existing?.jsonPayload;
      if (reviewStatus != null) {
        final payload = <String, dynamic>{};
        if (jsonPayload != null && jsonPayload.isNotEmpty) {
          try {
            payload.addAll(jsonDecode(jsonPayload) as Map<String, dynamic>);
          } catch (_) {}
        }
        payload['reviewStatus'] = reviewStatus;
        jsonPayload = jsonEncode(payload);
      }

      await db.into(db.localSeals).insertOnConflictUpdate(
            LocalSealsCompanion.insert(
              id: id,
              jobId: widget.jobId,
              floorId: widget.floorId,
              sealNumber: m['sealNumber'] as String,
              system: m['system'] as String? ?? existing?.system ?? '',
              construction: existing?.construction ?? '',
              location: existing?.location ?? '',
              fireRating: existing?.fireRating ?? '',
              status: Value(m['status'] as String? ?? 'draft'),
              version: Value(m['version'] as int? ?? 1),
              isSynced: Value(syncFlags.isSynced),
              syncConflict: Value(syncFlags.syncConflict),
              markerPlacementPending: Value(
                m['markerPlacementPending'] as bool? ??
                    existing?.markerPlacementPending ??
                    false,
              ),
              jsonPayload: Value(jsonPayload),
              updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                  DateTime.now(),
            ),
          );
    }
  }

  Future<List<Map<String, dynamic>>> _mergeWithUnsyncedLocal(
    AppDatabase db,
    List<Map<String, dynamic>> apiList,
  ) async {
    final localOnFloor = await (db.select(db.localSeals)
          ..where((s) =>
              s.floorId.equals(widget.floorId) & s.deletedAt.isNull()))
        .get();
    final photoCounts = await _photoCountsForSeals(
      db,
      localOnFloor.map((r) => r.id).toList(),
    );

    return mergeSealListWithLocalRows(
      apiList: apiList,
      localOnFloor: localOnFloor,
      mapLocal: (row) => mapLocalSealListRow(
        row,
        photoCount: photoCounts[row.id] ?? 0,
        isWorker: _isWorker,
      ),
    );
  }

  Future<void> _enrichWithLocalSyncFlags(
    AppDatabase db,
    List<Map<String, dynamic>> seals,
  ) async {
    final ids = seals.map((s) => s['id'] as String).toList();
    if (ids.isEmpty) return;

    final locals = await (db.select(db.localSeals)
          ..where((s) => s.id.isIn(ids)))
        .get();
    final byId = {for (final r in locals) r.id: r};

    for (final seal in seals) {
      final local = byId[seal['id'] as String];
      if (local == null) continue;
      seal['isSynced'] = local.isSynced;
      seal['syncConflict'] = local.syncConflict;
      seal['markerPlacementPending'] = local.markerPlacementPending;
    }
  }

  Future<Map<String, int>> _photoCountsForSeals(
    AppDatabase db,
    List<String> sealIds,
  ) async {
    if (sealIds.isEmpty) return {};
    final photos = await (db.select(db.localPhotos)
          ..where((p) => p.sealId.isIn(sealIds)))
        .get();
    final counts = <String, int>{};
    for (final p in photos) {
      counts[p.sealId] = (counts[p.sealId] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _loadFromDrift(AppDatabase db) async {
    final rows = await (db.select(db.localSeals)
          ..where(
              (s) => s.floorId.equals(widget.floorId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
        .get();

    final photoCounts = await _photoCountsForSeals(
      db,
      rows.map((r) => r.id).toList(),
    );
    final seals = rows
        .map((row) => mapLocalSealListRow(
              row,
              photoCount: photoCounts[row.id] ?? 0,
              isWorker: _isWorker,
            ))
        .toList();
    sortSealsByUpdatedAt(seals);
    final conflictIds = await _loadConflictSealIds(db, seals);
    await _persistFloorContext();
    await _enrichWithMarkerPlacement(db, seals);
    final drawingRow = await (db.select(db.localFloorDrawings)
          ..where((d) => d.floorId.equals(widget.floorId)))
        .getSingleOrNull();

    if (!mounted) return;
    setState(() {
      _seals = _applyActiveFilters(seals);
      _conflictSealIds = conflictIds;
      _hasDrawing = drawingRow != null;
      _dataSource = SealListDataSource.offline;
      _offlineHint = rows.isEmpty
          ? 'Server nedostupný a v cache nejsou žádné ucpávky pro toto patro.'
          : null;
      _loading = false;
    });
  }

  Future<void> _enrichWithMarkerPlacement(
    AppDatabase db,
    List<Map<String, dynamic>> seals,
  ) async {
    final markers = await (db.select(db.localSealMarkers)
          ..where((m) => m.floorId.equals(widget.floorId)))
        .get();
    final placed = markers.map((m) => m.sealId).toSet();
    for (final seal in seals) {
      seal['hasMarker'] = placed.contains(seal['id']);
    }
  }

  Future<bool> _loadDrawingAvailability(Dio dio, AppDatabase db) async {
    try {
      final res = await dio.get(
        '/api/jobs/${widget.jobId}/floors/${widget.floorId}/drawing',
      );
      return (res.data as Map)['drawing'] != null;
    } catch (_) {
      final row = await (db.select(db.localFloorDrawings)
            ..where((d) => d.floorId.equals(widget.floorId)))
          .getSingleOrNull();
      return row != null;
    }
  }

  void _openFloorPlan() {
    if (widget.jobId.isEmpty) return;
    context.push('/floor-plan/${widget.floorId}?jobId=${widget.jobId}');
  }

  Future<void> _uploadDrawing() async {
    final replacing = _hasDrawing == true;
    setState(() => _uploadingDrawing = true);
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
      if (mounted) setState(() => _uploadingDrawing = false);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Výkres smazán')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Smazání selhalo'))),
      );
    }
  }

  Future<void> _exportDrawingPdf() async {
    try {
      await exportFloorDrawingPdf(
        dio: ref.read(dioProvider),
        jobId: widget.jobId,
        floorId: widget.floorId,
        fileNameBase: 'vykres-${widget.floorId}',
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

  Widget _drawingActions(AuthService auth) {
    final canManage = auth.canManageFloorDrawings;
    final canExport = auth.canAccessReports && _hasDrawing == true;

    if (_hasDrawing != true && !canManage) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text('Výkres zatím není nahrán'),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (_hasDrawing == true)
          AppPrimaryButton(
            label: 'Otevřít výkres patra',
            icon: Icons.map_outlined,
            fullWidth: false,
            onPressed: _openFloorPlan,
          ),
        if (canManage && _hasDrawing != true)
          AppSecondaryButton(
            label: 'Nahrát výkres',
            icon: Icons.upload_file,
            fullWidth: false,
            onPressed: _uploadingDrawing ? null : _uploadDrawing,
          ),
        if (canManage && _hasDrawing == true) ...[
          AppSecondaryButton(
            label: 'Nahradit výkres',
            icon: Icons.upload_file,
            fullWidth: false,
            onPressed: _uploadingDrawing ? null : _uploadDrawing,
          ),
          AppSecondaryButton(
            label: 'Smazat výkres',
            icon: Icons.delete_outline,
            fullWidth: false,
            onPressed: _deleteDrawing,
          ),
        ],
        if (canExport)
          AppSecondaryButton(
            label: 'Export PDF',
            icon: Icons.picture_as_pdf_outlined,
            fullWidth: false,
            onPressed: _exportDrawingPdf,
          ),
      ],
    );
  }

  Future<Set<String>> _loadConflictSealIds(
    AppDatabase db,
    List<Map<String, dynamic>> seals,
  ) async {
    final ids = seals.map((s) => s['id'] as String).toList();
    if (ids.isEmpty) return {};

    final rows = await (db.select(db.localSeals)
          ..where((s) => s.id.isIn(ids) & s.syncConflict.equals(true)))
        .get();
    return rows.map((r) => r.id).toSet();
  }

  Future<void> _bulkStatus(String status) async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;

    String? comment;
    if (status == 'draft') {
      comment = await promptBulkReturnComment(context);
      if (comment == null || comment.isEmpty) return;
    } else {
      final ok = await confirmBulkAction(
        context,
        title: 'Schválit ucpávky',
        count: count,
        message: 'Označit $count ucpávek jako zkontrolované?',
      );
      if (!ok) return;
    }

    try {
      final res = await ref.read(dioProvider).post('/api/seals/bulk-status', data: {
        'ids': _selectedIds.toList(),
        'status': status,
        if (comment != null) 'comment': comment,
      });
      final data = res.data as Map<String, dynamic>?;
      final parsed = parseBulkResponse(data);
      setState(() => _selectedIds = {});
      await _load();
      if (!mounted || parsed == null) return;
      showBulkResultSnackBar(
        context,
        succeeded: parsed['succeeded'] as int,
        failed: parsed['failed'] as int,
        actionLabel: status == 'draft' ? 'Vrácení' : 'Schválení',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Chyba'))),
      );
    }
  }

  Future<void> _bulkMove() async {
    if (_selectedIds.isEmpty || widget.jobId.isEmpty) return;
    final count = _selectedIds.length;

    List<Map<String, dynamic>> floors = [];
    try {
      final res = await ref.read(dioProvider).get('/api/jobs/${widget.jobId}/floors');
      floors = (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patra nelze načíst (offline)')),
      );
      return;
    }

    final targets = floors
        .where((f) => f['id'] != widget.floorId)
        .cast<Map<String, dynamic>>()
        .toList();
    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Žádné jiné patro v zakázce')),
      );
      return;
    }

    if (!mounted) return;

    final target = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Přesunout na patro'),
        children: targets
            .map(
              (f) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, f),
                child: Text(f['name'] as String? ?? ''),
              ),
            )
            .toList(),
      ),
    );
    if (target == null || !mounted) return;

    final ok = await confirmBulkAction(
      context,
      title: 'Přesunout ucpávky',
      count: count,
      message:
          'Přesunout $count ucpávek na patro „${target['name']}“?',
    );
    if (!ok) return;

    try {
      final res = await ref.read(dioProvider).post('/api/seals/bulk-move', data: {
        'ids': _selectedIds.toList(),
        'floorId': target['id'],
      });
      final data = res.data as Map<String, dynamic>?;
      final parsed = parseBulkResponse(data);
      setState(() => _selectedIds = {});
      await _load();
      if (!mounted || parsed == null) return;
      showBulkResultSnackBar(
        context,
        succeeded: parsed['succeeded'] as int,
        failed: parsed['failed'] as int,
        actionLabel: 'Přesun',
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Chyba'))),
      );
    }
  }

  Future<void> _bulkExportCsv() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await confirmBulkAction(
      context,
      title: 'Export vybraných',
      count: count,
      message: 'Exportovat $count ucpávek do CSV?',
      confirmLabel: 'Exportovat',
    );
    if (!ok) return;

    try {
      final res = await ref.read(dioProvider).post(
        '/api/seals/bulk-export/csv',
        data: {'ids': _selectedIds.toList()},
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = normalizeExportBytes(res.data, exportLabel: 'CSV export');
      await saveExportFile(
        bytes: bytes,
        fileName: 'vybrane-ucpavky',
        extension: 'csv',
        exportLabel: 'CSV export',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exportováno $count ucpávek')),
      );
    } on ExportSaveCancelled {
      return;
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Export selhal'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export selhal: $e')),
      );
    }
  }

  void _selectAllVisible() {
    setState(() {
      _selectedIds = _seals.map((s) => s['id'] as String).toSet();
    });
  }

  bool get _canBulkSelect => ref.read(authServiceProvider).canReviewSeal;

  List<Map<String, dynamic>> _applyActiveFilters(
    List<Map<String, dynamic>> seals,
  ) {
    return applySealListFilters(
      seals,
      filters: _activeFilters,
      isWorker: _isWorker,
    );
  }

  void _toggleFilter(SealProblemFilter filter) {
    setState(() {
      if (_activeFilters.contains(filter)) {
        _activeFilters.remove(filter);
      } else {
        _activeFilters.add(filter);
      }
    });
    _load();
  }

  Widget _filterChips() {
    if (!_canBulkSelect) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: SealProblemFilter.values
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: FilterChip(
                  label: Text(f.label),
                  selected: _activeFilters.contains(f),
                  onSelected: (_) => _toggleFilter(f),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ucpávky'),
        actions: [
          const AppTopActions(),
          if (_dataSource == SealListDataSource.offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(compact: true)),
            ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Výkres patra',
            onPressed: widget.jobId.isEmpty
                ? null
                : () => context.push(
                      '/floor-plan/${widget.floorId}?jobId=${widget.jobId}',
                    ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          if (_canBulkSelect && _seals.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Vybrat vše',
              onPressed: _selectAllVisible,
            ),
        ],
      ),
      floatingActionButton: auth.isWorker || auth.isVedeni || auth.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context
                  .push('/seal/new?jobId=${widget.jobId}&floorId=${widget.floorId}'),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Nová'),
            )
          : null,
      bottomNavigationBar: _canBulkSelect && _selectedIds.isNotEmpty
          ? Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Text(
                      '${_selectedIds.length} vybráno',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'approve':
                            _bulkStatus('checked');
                          case 'return':
                            _bulkStatus('draft');
                          case 'move':
                            _bulkMove();
                          case 'export':
                            _bulkExportCsv();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'approve',
                          child: Text('Schválit'),
                        ),
                        const PopupMenuItem(
                          value: 'return',
                          child: Text('Vrátit k opravě'),
                        ),
                        if (auth.canAccessReports)
                          const PopupMenuItem(
                            value: 'export',
                            child: Text('Export CSV'),
                          ),
                        const PopupMenuItem(
                          value: 'move',
                          child: Text('Přesunout na patro'),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        child: Row(
                          children: [
                            Text('Akce'),
                            Icon(Icons.arrow_drop_up),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                JobContextBar(jobId: widget.jobId, floorName: _floorName),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: _drawingActions(auth),
                ),
                _filterChips(),
                if (_dataSource == SealListDataSource.offline)
                  Container(
                    margin: const EdgeInsets.all(AppSpacing.lg),
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
                                'Zobrazena poslední uložená data z zařízení.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.warning,
                                ),
                          ),
                        ),
                        TextButton(onPressed: _load, child: const Text('Zkusit znovu')),
                      ],
                    ),
                  ),
                if (_seals.isEmpty)
                  Expanded(
                    child: EmptyState(
                      message: _offlineHint ?? 'Na tomto patře zatím nejsou ucpávky.',
                      icon: Icons.inventory_2_outlined,
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _seals.length,
                      itemBuilder: (_, i) {
                        final s = _seals[i];
                        final id = s['id'] as String;
                        final hasConflict = _conflictSealIds.contains(id);
                        final selected = _selectedIds.contains(id);

                        return SealListRow(
                          seal: s,
                          isWorker: auth.isWorker,
                          hasConflict: hasConflict,
                          selected: selected,
                          showCheckbox: _canBulkSelect,
                          onTap: () {
                            if (_canBulkSelect && _selectedIds.isNotEmpty) {
                              setState(() {
                                if (selected) {
                                  _selectedIds.remove(id);
                                } else {
                                  _selectedIds.add(id);
                                }
                              });
                              return;
                            }
                            context.push('/seal/$id').then((_) => _load());
                          },
                          onSelectChanged: _canBulkSelect
                              ? (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedIds.add(id);
                                    } else {
                                      _selectedIds.remove(id);
                                    }
                                  });
                                }
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
