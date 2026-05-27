import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/theme.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';

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
  bool _loading = true;
  SealListDataSource? _dataSource;
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
      await _cacheSealsFromApi(db, apiList);
      final merged = await _mergeWithUnsyncedLocal(db, apiList);
      if (!mounted) return;
      setState(() {
        _seals = merged;
        _dataSource = SealListDataSource.online;
        _loading = false;
      });
    } on DioException catch (_) {
      await _loadFromDrift(db);
    } catch (_) {
      await _loadFromDrift(db);
    }
  }

  Future<void> _cacheSealsFromApi(AppDatabase db, List<Map<String, dynamic>> apiList) async {
    for (final m in apiList) {
      final id = m['id'] as String;
      final existing = await (db.select(db.localSeals)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

      await db.into(db.localSeals).insertOnConflictUpdate(
            LocalSealsCompanion.insert(
              id: id,
              jobId: widget.jobId,
              floorId: widget.floorId,
              sealNumber: m['sealNumber'] as String,
              system: existing?.system ?? '',
              construction: existing?.construction ?? '',
              location: existing?.location ?? '',
              fireRating: existing?.fireRating ?? '',
              status: Value(m['status'] as String? ?? 'draft'),
              version: Value(m['version'] as int? ?? 1),
              isSynced: const Value(true),
              syncConflict: const Value(false),
              updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now(),
            ),
          );
    }
  }

  Future<List<Map<String, dynamic>>> _mergeWithUnsyncedLocal(
    AppDatabase db,
    List<Map<String, dynamic>> apiList,
  ) async {
    final apiIds = apiList.map((e) => e['id'] as String).toSet();
    final pending = await (db.select(db.localSeals)
          ..where((s) => s.floorId.equals(widget.floorId) & s.isSynced.equals(false)))
        .get();

    final merged = [...apiList];
    for (final row in pending) {
      if (!apiIds.contains(row.id)) {
        merged.add(_mapLocalSealRow(row));
      }
    }
    merged.sort((a, b) => (a['sealNumber'] as String).compareTo(b['sealNumber'] as String));
    return merged;
  }

  Future<void> _loadFromDrift(AppDatabase db) async {
    final rows = await (db.select(db.localSeals)
          ..where((s) => s.floorId.equals(widget.floorId))
          ..orderBy([(s) => OrderingTerm.asc(s.sealNumber)]))
        .get();

    if (!mounted) return;
    setState(() {
      _seals = rows.map(_mapLocalSealRow).toList();
      _dataSource = SealListDataSource.offline;
      _offlineHint = rows.isEmpty
          ? 'Server nedostupný a v cache nejsou žádné ucpávky pro toto patro.'
          : null;
      _loading = false;
    });
  }

  static Map<String, dynamic> _mapLocalSealRow(LocalSeal row) => {
        'id': row.id,
        'sealNumber': row.sealNumber,
        'status': row.status,
        'version': row.version,
        'updatedAt': row.updatedAt.toIso8601String(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ucpávky na patře'),
        actions: [
          if (_dataSource == SealListDataSource.offline)
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/seal/new?jobId=${widget.jobId}&floorId=${widget.floorId}'),
        icon: const Icon(Icons.add),
        label: const Text('Nová'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_dataSource == SealListDataSource.offline)
                  MaterialBanner(
                    content: Text(
                      _offlineHint ??
                          'Zobrazena poslední uložená data z zařízení. Po připojení k serveru obnovte seznam.',
                    ),
                    leading: const Icon(Icons.cloud_off),
                    actions: [
                      TextButton(onPressed: _load, child: const Text('Zkusit znovu')),
                    ],
                  ),
                if (_seals.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        _offlineHint ?? 'Na tomto patře zatím nejsou ucpávky.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _seals.length,
                      itemBuilder: (_, i) {
                        final s = _seals[i];
                        final status = s['status'] as String? ?? 'draft';
                        return InkWell(
                          onTap: () {
                            context.push('/seal/${s['id']}').then((_) => _load());
                          },
                          child: Card(
                            color: AppTheme.statusColor(status).withValues(alpha: 0.2),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: AppTheme.statusColor(status),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    s['sealNumber'] as String,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
