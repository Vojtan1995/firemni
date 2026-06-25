import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reports/export_service.dart';

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
  String? _exportingWorksheetId;
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
    'archived': 'Archivovaný',
  };

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _bulkBusy = false;

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
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Chyba načtení'))),
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
    if (workers.isEmpty) {
      return ws['createdBy']?['displayName'] as String? ?? '—';
    }
    return workers
        .map((w) => (w['user'] as Map?)?['displayName'] ?? '')
        .where((s) => s.toString().isNotEmpty)
        .join(', ');
  }

  Future<void> _exportWorksheet(
    Map<String, dynamic> ws, {
    required String extension,
  }) async {
    final id = ws['id'] as String?;
    if (id == null || id.isEmpty) return;
    setState(() => _exportingWorksheetId = id);
    try {
      final res = await ref.read(dioProvider).get(
            '/api/worksheets/$id/export/$extension',
            options: Options(responseType: ResponseType.bytes),
          );
      final label = extension.toUpperCase();
      final bytes = normalizeExportBytes(res.data, exportLabel: label);
      final job = ws['job'] as Map<String, dynamic>?;
      final project = job?['projectNumber'] ?? 'soupis';
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final filePath = await saveExportFile(
        bytes: bytes,
        fileName: 'soupis_${project}_$date.$extension',
        extension: extension,
        exportLabel: label,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label uloženo: $filePath')),
      );
    } on ExportSaveCancelled {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uložení zrušeno')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Export selhal'))),
      );
    } finally {
      if (mounted) setState(() => _exportingWorksheetId = null);
    }
  }

  Widget _worksheetCard(Map<String, dynamic> ws, {bool canSelect = false}) {
    final id = ws['id'] as String? ?? '';
    final job = ws['job'] as Map<String, dynamic>?;
    final status = ws['status'] as String? ?? 'draft';
    final count = ws['_count']?['items'] ?? 0;
    final exporting = _exportingWorksheetId == ws['id'];
    final selected = _selectedIds.contains(id);
    return AppCard(
      title: '${job?['projectNumber'] ?? ''} ${job?['name'] ?? ''}'.trim(),
      subtitle:
          '${_floorsLabel(ws)} · ${_workersLabel(ws)} · ${_periodLabel(ws)} · $count položek',
      borderColor: selected ? AppColors.accent.withValues(alpha: 0.5) : null,
      leading: canSelect && _selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => setState(() {
                if (selected) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                }
              }),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(
            status: status,
            label: _statusLabels[status] ?? status,
            compact: true,
          ),
          const SizedBox(width: AppSpacing.xs),
          exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : PopupMenuButton<String>(
                  tooltip: 'Export',
                  icon: const Icon(Icons.download_outlined),
                  onSelected: (value) => _exportWorksheet(ws, extension: value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                    PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                  ],
                ),
        ],
      ),
      onTap: _selectionMode && canSelect
          ? () => setState(() {
                if (selected) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                }
              })
          : () => context.push('/worksheets/${ws['id']}'),
    );
  }

  Future<void> _bulkChangeStatus(String status) async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final label = _statusLabels[status] ?? status;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(status == 'archived' ? 'Archivovat soupisy' : 'Změnit stav'),
        content: Text('Označit $count soupisů jako "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Potvrdit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkBusy = true);
    try {
      final res = await ref
          .read(dioProvider)
          .post('/api/worksheets/bulk-status', data: {
        'ids': _selectedIds.toList(),
        'status': status,
      });
      final data = res.data as Map<String, dynamic>?;
      final updated = data?['updated'] as int? ?? 0;
      final failed = data?['failed'] as int? ?? 0;
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upraveno: $updated · Selhalo: $failed')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(apiErrorMessage(e, fallback: 'Hromadná akce selhala'))),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _bulkDeleteDrafts() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smazat soupisy'),
        content: Text(
          'Smazat $count vybraných soupisů? Smazat lze jen rozpracované soupisy, ostatní budou přeskočeny.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Smazat'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkBusy = true);
    var deleted = 0;
    var failed = 0;
    final dio = ref.read(dioProvider);
    for (final id in _selectedIds.toList()) {
      try {
        await dio.delete('/api/worksheets/$id');
        deleted++;
      } catch (_) {
        failed++;
      }
    }
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
      _bulkBusy = false;
    });
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Smazáno: $deleted · Selhalo: $failed')),
    );
  }

  Widget _buildWorksheetList(AuthService auth) {
    if (auth.isWorker) {
      final active =
          _worksheets.where((ws) => ws['status'] != 'archived').toList();
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: active.length,
        itemBuilder: (_, i) => _worksheetCard(active[i]),
      );
    }

    // Vedení: seznam pracovníků, po rozkliknutí jeho soupisy.
    // Soupis s více pracovníky se objeví u každého z nich. Archivované jdou
    // do samostatné složky „Archiv" mimo seznam pracovníků.
    final active = _worksheets.where((ws) => ws['status'] != 'archived');
    final archived =
        _worksheets.where((ws) => ws['status'] == 'archived').toList();

    final byWorker = <String, _WorkerGroup>{};
    for (final ws in active) {
      final workers =
          (ws['workers'] as List? ?? []).cast<Map<String, dynamic>>();
      if (workers.isEmpty) {
        final name = ws['createdBy']?['displayName'] as String? ?? '—';
        (byWorker[name] ??= _WorkerGroup(name)).add(ws);
      } else {
        for (final w in workers) {
          final user = w['user'] as Map<String, dynamic>?;
          final id = user?['id'] as String? ?? '';
          final name = user?['displayName'] as String? ?? '—';
          (byWorker[id.isEmpty ? name : id] ??= _WorkerGroup(name)).add(ws);
        }
      }
    }
    final groups = byWorker.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        for (final g in groups)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ExpansionTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(g.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(g.summaryLabel),
              initiallyExpanded: groups.length == 1,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: g.worksheets
                  .map((ws) => _worksheetCard(ws, canSelect: true))
                  .toList(),
            ),
          ),
        if (archived.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ExpansionTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text('Archiv (${archived.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: archived
                  .map((ws) => _worksheetCard(ws, canSelect: true))
                  .toList(),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.isWorker
            ? 'Moje uložené soupisy'
            : 'Soupisy podle pracovníků'),
        actions: [
          if (!auth.isWorker)
            IconButton(
              icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
              tooltip: _selectionMode ? 'Zrušit výběr' : 'Vybrat soupisy',
              onPressed: () => setState(() {
                _selectionMode = !_selectionMode;
                if (!_selectionMode) _selectedIds.clear();
              }),
            ),
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
                      DropdownMenuEntry(
                          value: 'false', label: 'Nevyfakturované'),
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
          if (_selectionMode && _selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('Vybráno: ${_selectedIds.length}')),
                  if (_bulkBusy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Akce',
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Akce'),
                          Icon(Icons.expand_more),
                        ],
                      ),
                      onSelected: (value) {
                        if (value == 'delete') {
                          _bulkDeleteDrafts();
                        } else {
                          _bulkChangeStatus(value);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'draft',
                          child: Text('Vrátit do rozpracovaného'),
                        ),
                        PopupMenuItem(
                          value: 'reviewed',
                          child: Text('Nastavit: Zkontrolovaný'),
                        ),
                        PopupMenuItem(
                          value: 'ready_for_invoice',
                          child: Text('Nastavit: Připravený k fakturaci'),
                        ),
                        PopupMenuItem(
                          value: 'invoiced',
                          child: Text('Nastavit: Vyfakturovaný'),
                        ),
                        PopupMenuItem(
                          value: 'archived',
                          child: Text('Archivovat'),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Smazat (jen rozpracované)',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Soupisy jednoho pracovníka + rozpad podle stavu pro přehled vedení.
class _WorkerGroup {
  _WorkerGroup(this.name);

  final String name;
  final List<Map<String, dynamic>> worksheets = [];
  final Map<String, int> _statusCounts = {};

  void add(Map<String, dynamic> ws) {
    worksheets.add(ws);
    final status = ws['status'] as String? ?? 'draft';
    _statusCounts[status] = (_statusCounts[status] ?? 0) + 1;
  }

  /// Např. „5 soupisů · 2 odevzdané · 1 zkontrolovaný".
  String get summaryLabel {
    final parts = <String>['${worksheets.length} soupisů'];
    final submitted = _statusCounts['submitted'] ?? 0;
    final reviewed = _statusCounts['reviewed'] ?? 0;
    final invoicing = (_statusCounts['ready_for_invoice'] ?? 0) +
        (_statusCounts['invoiced'] ?? 0);
    if (submitted > 0) parts.add('$submitted odevzdaných');
    if (reviewed > 0) parts.add('$reviewed zkontrolovaných');
    if (invoicing > 0) parts.add('$invoicing ve fakturaci');
    return parts.join(' · ');
  }
}
