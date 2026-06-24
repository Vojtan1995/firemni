import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../auth/auth_provider.dart';
import 'worksheet_create_helpers.dart';

class WorksheetsScreen extends ConsumerStatefulWidget {
  const WorksheetsScreen({super.key});

  @override
  ConsumerState<WorksheetsScreen> createState() => _WorksheetsScreenState();
}

class _WorksheetsScreenState extends ConsumerState<WorksheetsScreen> {
  List<Map<String, dynamic>> _worksheets = [];
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;
  String? _statusFilter;

  static const _statusLabels = {
    'draft': 'Rozpracovaný',
    'submitted': 'Odevzdaný',
    'reviewed': 'Zkontrolovaný',
    'ready_for_invoice': 'Připravený k fakturaci',
    'invoiced': 'Vyfakturovaný',
    'archived': 'Archivovaný',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final auth = ref.read(authServiceProvider);
    try {
      if (!auth.isWorker) {
        final filterRes = await dio.get('/api/reports/filter-options');
        _workers = ((filterRes.data as Map)['workers'] as List? ?? [])
            .cast<Map<String, dynamic>>();
      }
      if (!auth.isWorker) {
        final jobsRes = await dio.get('/api/jobs');
        _jobs = (jobsRes.data as List).cast<Map<String, dynamic>>();
      } else {
        final jobsRes = await dio.get('/api/jobs/my');
        _jobs = (jobsRes.data as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    try {
      final query = _statusFilter != null ? '?status=$_statusFilter' : '';
      final res = await dio.get('/api/worksheets$query');
      if (!mounted) return;
      setState(() {
        _worksheets = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createWorksheet() async {
    final auth = ref.read(authServiceProvider);
    if (_jobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nejdříve vyberte dostupnou zakázku')),
      );
      return;
    }
    String? selectedJobId = _jobs.first['id'] as String?;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nový soupis práce'),
          content: DropdownButtonFormField<String>(
            key: ValueKey(selectedJobId),
            initialValue: selectedJobId,
            decoration: const InputDecoration(labelText: 'Zakázka'),
            items: _jobs
                .map((j) => DropdownMenuItem(
                      value: j['id'] as String,
                      child: Text('${j['projectNumber']} ${j['name']}'),
                    ))
                .toList(),
            onChanged: (v) => setDialogState(() => selectedJobId = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
            FilledButton(
              onPressed: () async {
                if (selectedJobId == null) return;
                Navigator.pop(ctx);
                try {
                  List<String>? workerIds;
                  if (!auth.isWorker) {
                    workerIds = await pickWorksheetWorkerIds(
                      ctx,
                      workers: _workers,
                    );
                    if (workerIds == null || workerIds.isEmpty) return;
                  }

                  final body = <String, dynamic>{'jobId': selectedJobId};
                  if (workerIds != null) body['workerIds'] = workerIds;

                  final res = await ref.read(dioProvider).post('/api/worksheets', data: body);
                  final ws = res.data as Map<String, dynamic>;
                  final popRes = await ref.read(dioProvider).post(
                    '/api/worksheets/${ws['id']}/populate',
                    data: {},
                  );
                  await _load();
                  if (!mounted) return;
                  final pop = popRes.data as Map<String, dynamic>?;
                  final requested = (pop?['requestedCount'] as num?)?.toInt();
                  final added = (pop?['addedCount'] as num?)?.toInt();
                  if (requested != null && added != null && requested > added) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Do soupisu bylo přidáno $added z $requested položek. '
                          '${requested - added} je již součástí jiného soupisu.',
                        ),
                      ),
                    );
                  }
                } on DioException catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(apiErrorMessage(e, fallback: 'Chyba'))),
                  );
                }
              },
              child: const Text('Vytvořit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.isWorker ? 'Můj soupis práce' : 'Soupisy práce'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) {
              _statusFilter = v;
              _load();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Vše')),
              ..._statusLabels.entries.map(
                (e) => PopupMenuItem(value: e.key, child: Text(e.value)),
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: auth.canCreateWorksheet
          ? FloatingActionButton.extended(
              onPressed: _createWorksheet,
              icon: const Icon(Icons.add),
              label: const Text('Nový soupis'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _worksheets.isEmpty
              ? const Center(child: Text('Žádné soupisy'))
              : ListView.builder(
                  itemCount: _worksheets.length,
                  itemBuilder: (_, i) {
                    final ws = _worksheets[i];
                    final job = ws['job'] as Map<String, dynamic>?;
                    final status = ws['status'] as String? ?? 'draft';
                    final count = ws['_count']?['items'] ?? 0;
                    final id = ws['id'] as String;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(
                          '${job?['projectNumber'] ?? ''} ${job?['name'] ?? ''}'.trim(),
                        ),
                        subtitle: Text(
                          '${_statusLabels[status] ?? status} · $count položek',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final changed = await context.push<bool>('/worksheets/$id');
                          if (changed == true && mounted) _load();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
