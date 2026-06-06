import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../jobs/job_context_bar.dart';
import '../sync/sync_conflict.dart';

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
      final res = await dio.get('/api/seals/floors/${widget.floorId}/seals');
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
      final conflictIds = await _loadConflictSealIds(db, merged);
      if (!mounted) return;
      setState(() {
        _seals = merged;
        _conflictSealIds = conflictIds;
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
              updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                  DateTime.now(),
            ),
          );
    }
  }

  /// Merges API list with local rows missing from API (T2 / S1), including after sync.
  Future<List<Map<String, dynamic>>> _mergeWithUnsyncedLocal(
    AppDatabase db,
    List<Map<String, dynamic>> apiList,
  ) async {
    final localOnFloor = await (db.select(db.localSeals)
          ..where((s) =>
              s.floorId.equals(widget.floorId) & s.deletedAt.isNull()))
        .get();

    return mergeSealListWithLocalRows(
      apiList: apiList,
      localOnFloor: localOnFloor,
      mapLocal: _mapLocalSealRow,
    );
  }

  Future<void> _loadFromDrift(AppDatabase db) async {
    final rows = await (db.select(db.localSeals)
          ..where(
              (s) => s.floorId.equals(widget.floorId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.sealNumber)]))
        .get();

    final seals = rows.map(_mapLocalSealRow).toList();
    final conflictIds = await _loadConflictSealIds(db, seals);

    if (!mounted) return;
    setState(() {
      _seals = seals;
      _conflictSealIds = conflictIds;
      _dataSource = SealListDataSource.offline;
      _offlineHint = rows.isEmpty
          ? 'Server nedostupný a v cache nejsou žádné ucpávky pro toto patro.'
          : null;
      _loading = false;
    });
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

  static Map<String, dynamic> _mapLocalSealRow(LocalSeal row) => {
        'id': row.id,
        'sealNumber': row.sealNumber,
        'system': row.system,
        'fireRating': row.fireRating,
        'dimension': '',
        'status': row.status,
        'version': row.version,
        'photoCount': 0,
        'updatedAt': row.updatedAt.toIso8601String(),
      };

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Rozprac.';
      case 'checked':
        return 'Zkontrolováno';
      case 'invoiced':
        return 'Fakturováno';
      default:
        return status;
    }
  }

  Future<void> _bulkStatus(String status) async {
    if (_selectedIds.isEmpty) return;
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
      await ref.read(dioProvider).post('/api/seals/bulk-status', data: {
        'ids': _selectedIds.toList(),
        'status': status,
        if (comment != null) 'comment': comment,
      });
      setState(() => _selectedIds = {});
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Chyba')),
      );
    }
  }

  bool get _showWorkerColumn {
    final role = ref.read(authServiceProvider).role;
    return role == 'ucetni' || role == 'vedeni' || role == 'admin';
  }

  bool get _canBulkSelect => ref.read(authServiceProvider).canReviewSeal;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ucpávky'),
        actions: [
          if (_dataSource == SealListDataSource.offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(compact: true)),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
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
                    AppSecondaryButton(
                      label: 'Schválit',
                      fullWidth: false,
                      onPressed: () => _bulkStatus('checked'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppDangerButton(
                      label: 'Vrátit',
                      fullWidth: false,
                      onPressed: () => _bulkStatus('draft'),
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
                        final status = s['status'] as String? ?? 'draft';
                        final hasConflict = _conflictSealIds.contains(id);
                        final worker = s['worker'] as Map<String, dynamic>?;
                        final selected = _selectedIds.contains(id);

                        final subtitleParts = [
                          s['dimension'] ?? '',
                          s['fireRating'] ?? '',
                          if (_showWorkerColumn && worker != null)
                            worker['displayName'] ?? '',
                        ].where((x) => x.toString().isNotEmpty);

                        return AppCard(
                          borderColor: selected
                              ? AppColors.accent.withValues(alpha: 0.5)
                              : hasConflict
                                  ? AppColors.error.withValues(alpha: 0.4)
                                  : null,
                          showChevron: false,
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
                          child: Row(
                            children: [
                              if (_canBulkSelect)
                                Checkbox(
                                  value: selected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIds.add(id);
                                      } else {
                                        _selectedIds.remove(id);
                                      }
                                    });
                                  },
                                )
                              else
                                Icon(
                                  hasConflict ? Icons.warning_amber : Icons.circle,
                                  size: 12,
                                  color: hasConflict
                                      ? AppColors.error
                                      : AppTheme.statusColor(status),
                                ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '#${s['sealNumber']} · ${s['system'] ?? ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    if (subtitleParts.isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        subtitleParts.join(' · '),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              StatusBadge(
                                status: status,
                                conflict: hasConflict,
                                label: _statusLabel(status),
                                compact: true,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Icon(Icons.photo_camera_outlined,
                                  size: 14, color: AppColors.textMuted),
                              Text(
                                '${s['photoCount'] ?? 0}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Icon(Icons.chevron_right, color: AppColors.textMuted),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
