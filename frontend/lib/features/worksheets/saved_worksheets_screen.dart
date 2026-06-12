import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';

class SavedWorksheetsScreen extends ConsumerStatefulWidget {
  const SavedWorksheetsScreen({super.key});

  @override
  ConsumerState<SavedWorksheetsScreen> createState() =>
      _SavedWorksheetsScreenState();
}

class _SavedWorksheetsScreenState extends ConsumerState<SavedWorksheetsScreen> {
  List<Map<String, dynamic>> _worksheets = [];
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;
  String? _statusFilter;
  String? _jobIdFilter;
  String? _workerIdFilter;
  String? _invoicedFilter;

  static const _statusLabels = {
    'draft': 'Rozpracovaný',
    'submitted': 'Odevzdaný',
    'reviewed': 'Zkontrolovaný',
    'ready_for_invoice': 'Připravený k fakturaci',
    'invoiced': 'Vyfakturovaný',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    try {
      final filterRes = await dio.get('/api/reports/filter-options');
      if (mounted) {
        _jobs = ((filterRes.data as Map)['jobs'] as List)
            .cast<Map<String, dynamic>>();
        _workers = ((filterRes.data as Map)['workers'] as List? ?? [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    try {
      final params = <String, String>{};
      if (_statusFilter != null) params['status'] = _statusFilter!;
      if (_jobIdFilter != null) params['jobId'] = _jobIdFilter!;
      if (_workerIdFilter != null) params['workerId'] = _workerIdFilter!;
      if (_invoicedFilter != null) params['invoiced'] = _invoicedFilter!;
      final res = await dio.get(
        '/api/worksheets',
        queryParameters: params.isEmpty ? null : params,
      );
      if (!mounted) return;
      setState(() {
        _worksheets = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Chyba načtení')),
      );
    }
  }

  String _periodLabel(Map<String, dynamic> ws) {
    final from = ws['periodFrom'] as String?;
    final to = ws['periodTo'] as String?;
    if (from == null && to == null) return '—';
    return '${from?.split('T').first ?? '—'} – ${to?.split('T').first ?? '—'}';
  }

  String _floorsLabel(Map<String, dynamic> ws) {
    final names = (ws['floorNames'] as List?)?.cast<String>() ?? [];
    if (names.isEmpty) return '—';
    return names.join(', ');
  }

  String _workersLabel(Map<String, dynamic> ws) {
    final workers = (ws['workers'] as List? ?? []).cast<Map<String, dynamic>>();
    if (workers.isEmpty) return ws['createdBy']?['displayName'] as String? ?? '—';
    return workers
        .map((w) => (w['user'] as Map?)?['displayName'] ?? '')
        .where((s) => s.toString().isNotEmpty)
        .join(', ');
  }

  Widget _worksheetCard(Map<String, dynamic> ws) {
    final job = ws['job'] as Map<String, dynamic>?;
    final status = ws['status'] as String? ?? 'draft';
    final count = ws['_count']?['items'] ?? 0;
    return AppCard(
      title: '${job?['projectNumber'] ?? ''} ${job?['name'] ?? ''}'.trim(),
      subtitle:
          '${_floorsLabel(ws)} · ${_workersLabel(ws)} · ${_periodLabel(ws)} · $count položek',
      trailing: StatusBadge(
        status: status,
        label: _statusLabels[status] ?? status,
        compact: true,
      ),
      onTap: () => context.push('/worksheets/${ws['id']}'),
    );
  }

  Widget _buildWorksheetList(AuthService auth) {
    if (auth.isWorker) {
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _worksheets.length,
        itemBuilder: (_, i) => _worksheetCard(_worksheets[i]),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final ws in _worksheets) {
      final key = _workersLabel(ws);
      grouped.putIfAbsent(key, () => []).add(ws);
    }
    final keys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final name = keys[i];
        final items = grouped[name]!;
        return ExpansionTile(
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${items.length} soupisů'),
          initiallyExpanded: i == 0,
          children: items.map(_worksheetCard).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.isWorker ? 'Moje uložené soupisy' : 'Uložené soupisy'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (!auth.isWorker)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  DropdownMenu<String?>(
                    label: const Text('Stav'),
                    initialSelection: _statusFilter,
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(value: null, label: 'Vše'),
                      ..._statusLabels.entries.map(
                        (e) => DropdownMenuEntry(value: e.key, label: e.value),
                      ),
                    ],
                    onSelected: (v) {
                      _statusFilter = v;
                      _load();
                    },
                  ),
                  DropdownMenu<String?>(
                    label: const Text('Zakázka'),
                    initialSelection: _jobIdFilter,
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(value: null, label: 'Vše'),
                      ..._jobs.map(
                        (j) => DropdownMenuEntry(
                          value: j['id'] as String,
                          label: '${j['projectNumber']} ${j['name']}',
                        ),
                      ),
                    ],
                    onSelected: (v) {
                      _jobIdFilter = v;
                      _load();
                    },
                  ),
                  DropdownMenu<String?>(
                    label: const Text('Pracovník'),
                    initialSelection: _workerIdFilter,
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(value: null, label: 'Všichni'),
                      ..._workers.map(
                        (w) => DropdownMenuEntry(
                          value: w['id'] as String,
                          label: w['displayName'] as String? ?? '',
                        ),
                      ),
                    ],
                    onSelected: (v) {
                      _workerIdFilter = v;
                      _load();
                    },
                  ),
                  DropdownMenu<String?>(
                    label: const Text('Fakturace'),
                    initialSelection: _invoicedFilter,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: null, label: 'Vše'),
                      DropdownMenuEntry(value: 'true', label: 'Vyfakturované'),
                      DropdownMenuEntry(value: 'false', label: 'Nevyfakturované'),
                    ],
                    onSelected: (v) {
                      _invoicedFilter = v;
                      _load();
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _worksheets.isEmpty
                    ? const EmptyState(
                        message: 'Žádné uložené soupisy',
                        icon: Icons.description_outlined,
                      )
                    : _buildWorksheetList(auth),
          ),
        ],
      ),
    );
  }
}
