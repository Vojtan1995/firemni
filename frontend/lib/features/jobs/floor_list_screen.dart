import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reports/export_service.dart';
import 'floor_plan/floor_drawing_service.dart';
import 'job_context_bar.dart';
import 'work_context_service.dart';

/// Zda seznam pochází z API nebo z lokální cache (FE-02).
enum FloorListDataSource { online, offline }

class FloorListScreen extends ConsumerStatefulWidget {
  const FloorListScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<FloorListScreen> createState() => _FloorListScreenState();
}

class _FloorListScreenState extends ConsumerState<FloorListScreen> {
  List<Map<String, dynamic>> _floors = [];
  bool _loading = true;
  FloorListDataSource? _dataSource;
  String? _offlineHint;
  String? _uploadingFloorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _persistJobContext() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await WorkContextService(ref.read(databaseProvider)).saveJob(
      userId: userId,
      jobId: widget.jobId,
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
      final res = await dio.get('/api/jobs/${widget.jobId}/floors');
      final apiList = (res.data as List).cast<Map<String, dynamic>>();
      await _cacheFloorsFromApi(db, apiList);
      await _persistJobContext();
      if (!mounted) return;
      setState(() {
        _floors = apiList;
        _dataSource = FloorListDataSource.online;
        _loading = false;
      });
    } on DioException catch (_) {
      await _loadFromDrift(db);
    } catch (_) {
      await _loadFromDrift(db);
    }
  }

  Future<void> _cacheFloorsFromApi(
      AppDatabase db, List<Map<String, dynamic>> apiList) async {
    for (final m in apiList) {
      await db.into(db.localFloors).insertOnConflictUpdate(
            LocalFloorsCompanion.insert(
              id: m['id'] as String,
              jobId: widget.jobId,
              name: m['name'] as String,
              sortOrder: Value(m['sortOrder'] as int? ?? 0),
              updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                  DateTime.now(),
            ),
          );
    }
  }

  Future<void> _loadFromDrift(AppDatabase db) async {
    final rows = await (db.select(db.localFloors)
          ..where((f) => f.jobId.equals(widget.jobId) & f.deletedAt.isNull())
          ..orderBy([
            (f) => OrderingTerm.asc(f.sortOrder),
            (f) => OrderingTerm.asc(f.name)
          ]))
        .get();
    final drawingRows = await db.select(db.localFloorDrawings).get();
    final drawingFloorIds = drawingRows.map((d) => d.floorId).toSet();

    if (!mounted) return;
    await _persistJobContext();
    setState(() {
      _floors = rows
          .map((row) => {
                ..._mapLocalFloorRow(row),
                'hasDrawing': drawingFloorIds.contains(row.id),
              })
          .toList();
      _dataSource = FloorListDataSource.offline;
      _offlineHint = rows.isEmpty
          ? 'Server nedostupný a v cache nejsou žádná patra pro tuto stavbu.'
          : null;
      _loading = false;
    });
  }

  static Map<String, dynamic> _mapLocalFloorRow(LocalFloor row) => {
        'id': row.id,
        'jobId': row.jobId,
        'name': row.name,
        'sortOrder': row.sortOrder,
        'updatedAt': row.updatedAt.toIso8601String(),
        'hasDrawing': false,
      };

  Future<void> _openSeals(Map<String, dynamic> floor) async {
    final userId = ref.read(currentUserIdProvider);
    final db = ref.read(databaseProvider);
    if (userId != null) {
      await WorkContextService(db).saveFloor(
        userId: userId,
        jobId: widget.jobId,
        floorId: floor['id'] as String,
        floorName: floor['name'] as String?,
      );
    }
    if (!mounted) return;
    context.push('/seals/${floor['id']}?jobId=${widget.jobId}');
  }

  Future<void> _uploadDrawing(Map<String, dynamic> floor) async {
    final floorId = floor['id'] as String;
    final replacing = floor['hasDrawing'] == true;
    setState(() => _uploadingFloorId = floorId);
    try {
      final uploaded = await pickAndUploadFloorDrawing(
        dio: ref.read(dioProvider),
        jobId: widget.jobId,
        floorId: floorId,
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
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Upload selhal')),
      );
    } finally {
      if (mounted) setState(() => _uploadingFloorId = null);
    }
  }

  Future<void> _deleteDrawing(Map<String, dynamic> floor) async {
    final floorId = floor['id'] as String;
    try {
      final deleted = await confirmAndDeleteFloorDrawing(
        context: context,
        dio: ref.read(dioProvider),
        jobId: widget.jobId,
        floorId: floorId,
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
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Smazání selhalo')),
      );
    }
  }

  Future<void> _exportDrawing(Map<String, dynamic> floor) async {
    try {
      await exportFloorDrawingPdf(
        dio: ref.read(dioProvider),
        jobId: widget.jobId,
        floorId: floor['id'] as String,
        fileNameBase: 'vykres-${floor['id']}',
      );
    } on ExportSaveCancelled {
      // user dismissed save dialog
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Export selhal')),
      );
    }
  }

  void _onFloorMenuAction(String action, Map<String, dynamic> floor) {
    switch (action) {
      case 'seals':
        _openSeals(floor);
      case 'plan':
        context.push('/floor-plan/${floor['id']}?jobId=${widget.jobId}');
      case 'upload':
        _uploadDrawing(floor);
      case 'delete':
        _deleteDrawing(floor);
      case 'export':
        _exportDrawing(floor);
    }
  }

  List<PopupMenuEntry<String>> _floorMenuItems(
    AuthService auth,
    Map<String, dynamic> floor,
  ) {
    final hasDrawing = floor['hasDrawing'] == true;
    final canManage = auth.canManageFloorDrawings;
    final canExport = auth.canAccessReports;
    return [
      const PopupMenuItem(value: 'seals', child: Text('Otevřít ucpávky')),
      const PopupMenuItem(value: 'plan', child: Text('Otevřít výkres')),
      if (canManage)
        PopupMenuItem(
          value: 'upload',
          child: Text(hasDrawing ? 'Nahradit výkres' : 'Nahrát výkres'),
        ),
      if (canManage && hasDrawing)
        const PopupMenuItem(value: 'delete', child: Text('Smazat výkres')),
      if (canExport && hasDrawing)
        const PopupMenuItem(value: 'export', child: Text('Export PDF')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Výběr patra'),
        actions: [
          if (_dataSource == FloorListDataSource.offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(label: 'Offline data', compact: true)),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                JobContextBar(jobId: widget.jobId),
                if (_dataSource == FloorListDataSource.offline)
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
                                'Zobrazena poslední uložená patra ze zařízení. Po připojení k serveru obnovte seznam.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.warning,
                                ),
                          ),
                        ),
                        TextButton(onPressed: _load, child: const Text('Zkusit znovu')),
                      ],
                    ),
                  ),
                if (_floors.isEmpty)
                  Expanded(
                    child: EmptyState(
                      message: _offlineHint ??
                          'Pro tuto stavbu nejsou k dispozici žádná patra.',
                      icon: Icons.layers_outlined,
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: _floors.length,
                      itemBuilder: (_, i) {
                        final f = _floors[i];
                        final floorId = f['id'] as String;
                        final uploading = _uploadingFloorId == floorId;
                        return AppCard(
                          leading: AppIconBox(
                            icon: Icons.layers,
                            backgroundColor: AppColors.bgSecondary,
                            color: AppColors.textSecondary,
                          ),
                          title: f['name'] as String,
                          subtitle: f['hasDrawing'] == true
                              ? 'Výkres nahrán'
                              : null,
                          trailing: uploading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : PopupMenuButton<String>(
                                  onSelected: (v) => _onFloorMenuAction(v, f),
                                  itemBuilder: (_) => _floorMenuItems(auth, f),
                                ),
                          onTap: () => _openSeals(f),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
