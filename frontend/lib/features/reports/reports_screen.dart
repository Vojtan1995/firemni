import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../core/parse_utils.dart';
import '../auth/auth_provider.dart';
import '../seals/seal_constants.dart';
import 'export_service.dart';
import 'reports_query.dart';

class ReportsFilterSelection {
  const ReportsFilterSelection({
    required this.queryParams,
    required this.workerIds,
    this.jobId,
    this.status,
    this.workerId,
    this.floorId,
    this.system,
    this.entryType,
    this.from,
    this.to,
  });

  final Map<String, String> queryParams;
  final List<String> workerIds;
  final String? jobId;
  final String? status;
  final String? workerId;
  final String? floorId;
  final String? system;
  final String? entryType;
  final DateTime? from;
  final DateTime? to;
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    super.key,
    this.compact = false,
    this.hideLoadButton = false,
    this.initialJobId,
    this.initialStatus,
    this.initialWorkerId,
    this.onCreateWorksheet,
    this.worksheetActionLoading = false,
  });

  /// Bez Scaffold a bez tabulky — pro vložení do [SoupisyScreen].
  final bool compact;
  final bool hideLoadButton;
  final String? initialJobId;
  final String? initialStatus;
  final String? initialWorkerId;
  final Future<void> Function(ReportsFilterSelection filters)?
      onCreateWorksheet;
  final bool worksheetActionLoading;

  @override
  ConsumerState<ReportsScreen> createState() => ReportsScreenState();
}

class ReportsScreenState extends ConsumerState<ReportsScreen> {
  List<Map<String, dynamic>> _rows = [];
  double? _totalCzk;
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _floors = [];
  bool _loading = false;
  bool _exporting = false;
  String? _filterJobId;
  String? _filterStatus;
  String? _filterWorkerId;
  String? _filterFloorId;
  String? _filterSystem;
  String? _filterEntryType;
  DateTime? _filterFrom;
  DateTime? _filterTo;

  static const _statusOptions = <String?, String>{
    null: 'Všechny statusy',
    'draft': 'Koncept',
    'checked': 'Zkontrolováno',
    'invoiced': 'Vyfakturováno',
  };

  bool get _isWorker => ref.read(authServiceProvider).isWorker;

  Map<String, String> get _queryParams => buildReportsQueryParams(
        jobId: _filterJobId,
        status: _filterStatus,
        workerId: _isWorker ? ref.read(currentUserIdProvider) : _filterWorkerId,
        floorId: _filterFloorId,
        system: _filterSystem,
        entryType: _filterEntryType,
        from: _filterFrom,
        to: _filterTo,
      );

  ReportsFilterSelection get currentFilters {
    final currentUserId = ref.read(currentUserIdProvider);
    final isWorker = _isWorker;
    final workerIds = isWorker
        ? <String>[if (currentUserId != null) currentUserId]
        : _filterWorkerId != null
            ? <String>[_filterWorkerId!]
            : _workers
                .map((w) => w['id'] as String?)
                .whereType<String>()
                .toList();
    return ReportsFilterSelection(
      queryParams: _queryParams,
      workerIds: workerIds,
      jobId: _filterJobId,
      status: _filterStatus,
      workerId: isWorker ? currentUserId : _filterWorkerId,
      floorId: _filterFloorId,
      system: _filterSystem,
      entryType: _filterEntryType,
      from: _filterFrom,
      to: _filterTo,
    );
  }

  @override
  void initState() {
    super.initState();
    _filterJobId = widget.initialJobId;
    _filterStatus = widget.initialStatus;
    _filterWorkerId = widget.initialWorkerId;
    _loadFilterOptions();
  }

  /// Aplikuje filtry z drill-down navigace (volá [SoupisyScreen]).
  Future<void> applyInitialFilters({
    String? jobId,
    String? status,
    String? workerId,
  }) async {
    setState(() {
      if (jobId != null) _filterJobId = jobId.isEmpty ? null : jobId;
      if (status != null) _filterStatus = status.isEmpty ? null : status;
      if (workerId != null) {
        _filterWorkerId = workerId.isEmpty ? null : workerId;
      }
    });
    if (_filterJobId != null) {
      await _loadFloorsForJob(_filterJobId);
    }
    await _load();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final res =
          await ref.read(dioProvider).get('/api/reports/filter-options');
      if (!mounted) return;
      final data = res.data as Map;
      setState(() {
        _jobs = (data['jobs'] as List).cast<Map<String, dynamic>>();
        if (!_isWorker) {
          _workers = (data['workers'] as List).cast<Map<String, dynamic>>();
        }
      });
      if (_filterJobId != null) {
        await _loadFloorsForJob(_filterJobId);
      }
      if (widget.initialJobId != null ||
          widget.initialStatus != null ||
          widget.initialWorkerId != null) {
        await _load();
      }
    } on DioException catch (e) {
      _showError(_dioMessage(e, 'Nepodařilo se načíst filtry'));
    }
  }

  Future<void> _loadFloorsForJob(String? jobId) async {
    if (jobId == null || jobId.isEmpty) {
      setState(() {
        _floors = [];
        _filterFloorId = null;
      });
      return;
    }
    try {
      final res = await ref.read(dioProvider).get('/api/jobs/$jobId/floors');
      if (!mounted) return;
      setState(() {
        _floors = (res.data as List).cast<Map<String, dynamic>>();
        if (_filterFloorId != null &&
            !_floors.any((f) => f['id'] == _filterFloorId)) {
          _filterFloorId = null;
        }
      });
    } on DioException catch (e) {
      _showError(_dioMessage(e, 'Nepodařilo se načíst patra'));
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_filterFrom ?? DateTime.now())
        : (_filterTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _filterFrom = picked;
      } else {
        _filterTo = picked;
      }
    });
  }

  String _formatFilterDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('d.M.yyyy').format(d);
  }

  Future<void> load() => _load();

  Future<void> refreshFilterOptions() => _loadFilterOptions();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get(
            '/api/reports/work-summary',
            queryParameters: _queryParams,
          );
      if (!mounted) return;
      setState(() {
        final data = res.data as Map;
        _rows = (data['rows'] as List).cast<Map<String, dynamic>>();
        _totalCzk = parseNumOrNull(data['totalCzk']);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(_dioMessage(e, 'Nepodařilo se načíst soupis'));
    }
  }

  Future<void> _exportCsv() async {
    await _exportFile(
      path: '/api/reports/export/csv',
      extension: 'csv',
      successLabel: 'CSV',
      errorLabel: 'Export CSV selhal',
    );
  }

  Future<void> _exportPdf() async {
    await _exportFile(
      path: '/api/reports/export/pdf',
      extension: 'pdf',
      successLabel: 'PDF',
      errorLabel: 'Export PDF selhal',
    );
  }

  Future<void> _exportFile({
    required String path,
    required String extension,
    required String successLabel,
    required String errorLabel,
  }) async {
    setState(() => _exporting = true);
    try {
      logExport('$successLabel generation started');

      final res = await ref.read(dioProvider).get(
            path,
            queryParameters: _queryParams,
            options: Options(responseType: ResponseType.bytes),
          );

      final bytes = normalizeExportBytes(res.data, exportLabel: successLabel);
      logExport('$successLabel generated successfully');
      logExport('$successLabel bytes length: ${bytes.length}');

      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final defaultName = 'soupis_praci_$date.$extension';

      final filePath = await saveExportFile(
        bytes: bytes,
        fileName: defaultName,
        extension: extension,
        exportLabel: successLabel,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successLabel uloženo: $filePath')),
      );
    } on ExportSaveCancelled {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uložení zrušeno')),
      );
    } on DioException catch (e) {
      _showError(_dioMessage(e, errorLabel));
    } catch (e) {
      _showError('$errorLabel: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  String _dioMessage(DioException e, String fallback) =>
      apiErrorMessage(e, fallback: fallback);

  Map<String, String> get queryParams => _queryParams;

  Widget _dropdownLabel(String text) =>
      Text(text, overflow: TextOverflow.ellipsis);

  Widget _buildFiltersPanel(BuildContext context, bool isWorker) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            key: ValueKey('filter-job-$_filterJobId'),
            isExpanded: true,
            initialValue: _filterJobId,
            decoration: const InputDecoration(
              labelText: 'Stavba',
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: _dropdownLabel('Všechny stavby'),
              ),
              ..._jobs.map(
                (j) => DropdownMenuItem<String?>(
                  value: j['id'] as String,
                  child: _dropdownLabel(
                    '${j['projectNumber']} – ${j['name']}',
                  ),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _filterJobId = v);
              _loadFloorsForJob(v);
            },
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('filter-floor-$_filterFloorId-$_filterJobId'),
              isExpanded: true,
              initialValue: _filterFloorId,
              decoration: const InputDecoration(
                labelText: 'Patro',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: _dropdownLabel('Všechna patra'),
                ),
                ..._floors.map(
                  (f) => DropdownMenuItem<String?>(
                    value: f['id'] as String,
                    child: _dropdownLabel(f['name'] as String),
                  ),
                ),
              ],
              onChanged: _filterJobId == null
                  ? null
                  : (v) => setState(() => _filterFloorId = v),
            ),
            if (!isWorker) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('filter-worker-$_filterWorkerId'),
                isExpanded: true,
                initialValue: _filterWorkerId,
                decoration: const InputDecoration(
                  labelText: 'Pracovník',
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: _dropdownLabel('Všichni pracovníci'),
                  ),
                  ..._workers.map(
                    (w) => DropdownMenuItem<String?>(
                      value: w['id'] as String,
                      child: _dropdownLabel(
                        w['displayName'] as String? ?? w['username'] as String,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _filterWorkerId = v),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('filter-status-$_filterStatus'),
              isExpanded: true,
              initialValue: _filterStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: _statusOptions.entries
                  .map(
                    (e) => DropdownMenuItem<String?>(
                      value: e.key,
                      child: _dropdownLabel(e.value),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _filterStatus = v),
            ),
          ],
          if (!widget.compact) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('filter-system-$_filterSystem'),
              isExpanded: true,
              initialValue: _filterSystem,
              decoration: const InputDecoration(
                labelText: 'Systém',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: _dropdownLabel('Všechny systémy'),
                ),
                ...sealSystems.map(
                  (s) => DropdownMenuItem<String?>(
                    value: s,
                    child: _dropdownLabel(s),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _filterSystem = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('filter-entry-$_filterEntryType'),
              isExpanded: true,
              initialValue: _filterEntryType,
              decoration: const InputDecoration(
                labelText: 'Typ prostupu',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: _dropdownLabel('Všechny typy'),
                ),
                ...entryTypes.map(
                  (t) => DropdownMenuItem<String?>(
                    value: t,
                    child: _dropdownLabel(t),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _filterEntryType = v),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isFrom: true),
                  child: Text('Od: ${_formatFilterDate(_filterFrom)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isFrom: false),
                  child: Text('Do: ${_formatFilterDate(_filterTo)}'),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _filterFrom == null && _filterTo == null
                  ? null
                  : () => setState(() {
                        _filterFrom = null;
                        _filterTo = null;
                      }),
              child: const Text('Vymazat období'),
            ),
          ),
          if (!widget.hideLoadButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _load,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Načíst'),
              ),
            ),
          ],
          if (!widget.compact) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _exporting ? null : _exportCsv,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Export CSV'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _exporting ? null : _exportPdf,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: const Text('Export PDF'),
                  ),
                ),
              ],
            ),
          ],
          if (widget.onCreateWorksheet != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.worksheetActionLoading
                    ? null
                    : () => widget.onCreateWorksheet!(currentFilters),
                icon: widget.worksheetActionLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_check),
                label: const Text('Vytvořit soupis z filtrů'),
              ),
            ),
          ],
          if (!widget.hideLoadButton && _totalCzk != null) ...[
            const SizedBox(height: 8),
            Text(
              'Součet bez DPH: ${_totalCzk!.toStringAsFixed(2)} Kč',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWorker = ref.watch(authServiceProvider).isWorker;
    if (widget.compact) {
      return _buildFiltersPanel(context, isWorker);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(isWorker ? 'Můj soupis prací' : 'Soupis prací'),
      ),
      body: Column(
        children: [
          _buildFiltersPanel(context, isWorker),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final lineTotal = parseNumOrNull(r['cenaCelkem']);
                      final priceSuffix = lineTotal != null
                          ? ' | ${lineTotal.toStringAsFixed(2)} Kč'
                          : '';
                      return ListTile(
                        title: Text('${r['stavba']} | #${r['cisloUcpavky']}'),
                        subtitle: Text(
                          '${r['typProstupu']} – ${r['kusy']} ks$priceSuffix',
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
