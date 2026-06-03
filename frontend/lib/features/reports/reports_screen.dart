import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../seals/seal_constants.dart';
import 'reports_query.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  List<Map<String, dynamic>> _rows = [];
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

  Map<String, String> get _queryParams => buildReportsQueryParams(
        jobId: _filterJobId,
        status: _filterStatus,
        workerId: _filterWorkerId,
        floorId: _filterFloorId,
        system: _filterSystem,
        entryType: _filterEntryType,
        from: _filterFrom,
        to: _filterTo,
      );

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _loadWorkers();
  }

  Future<void> _loadJobs() async {
    try {
      final res = await ref.read(dioProvider).get(
        '/api/jobs',
        queryParameters: {'archived': 'false'},
      );
      if (!mounted) return;
      setState(() => _jobs = (res.data as List).cast<Map<String, dynamic>>());
    } on DioException catch (e) {
      _showError(_dioMessage(e, 'Nepodařilo se načíst stavby'));
    }
  }

  Future<void> _loadWorkers() async {
    try {
      final res = await ref.read(dioProvider).get('/api/users');
      if (!mounted) return;
      final all = (res.data as List).cast<Map<String, dynamic>>();
      setState(() {
        _workers = all.where((u) => u['role'] == 'worker').toList();
      });
    } on DioException catch (e) {
      _showError(_dioMessage(e, 'Nepodařilo se načíst pracovníky'));
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
      final res =
          await ref.read(dioProvider).get('/api/jobs/$jobId/floors');
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get(
            '/api/reports/work-summary',
            queryParameters: _queryParams,
          );
      if (!mounted) return;
      setState(() {
        _rows =
            ((res.data as Map)['rows'] as List).cast<Map<String, dynamic>>();
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
      final res = await ref.read(dioProvider).get(
            path,
            queryParameters: _queryParams,
            options: Options(responseType: ResponseType.bytes),
          );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Export vrátil prázdný soubor');
      }

      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final defaultName = 'soupis_praci_$date.$extension';

      String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Uložit $successLabel',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );

      if (filePath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uložení zrušeno')),
        );
        return;
      }

      if (!filePath.toLowerCase().endsWith('.$extension')) {
        filePath = '$filePath.$extension';
      }

      await File(filePath).writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successLabel uloženo: $filePath')),
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
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  String _dioMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soupis prací')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String?>(
                  value: _filterJobId,
                  decoration: const InputDecoration(
                    labelText: 'Stavba',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Všechny stavby'),
                    ),
                    ..._jobs.map(
                      (j) => DropdownMenuItem<String?>(
                        value: j['id'] as String,
                        child: Text('${j['projectNumber']} – ${j['name']}'),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _filterJobId = v);
                    _loadFloorsForJob(v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _filterFloorId,
                  decoration: const InputDecoration(
                    labelText: 'Patro',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Všechna patra'),
                    ),
                    ..._floors.map(
                      (f) => DropdownMenuItem<String?>(
                        value: f['id'] as String,
                        child: Text(f['name'] as String),
                      ),
                    ),
                  ],
                  onChanged: _filterJobId == null
                      ? null
                      : (v) => setState(() => _filterFloorId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _filterWorkerId,
                  decoration: const InputDecoration(
                    labelText: 'Pracovník',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Všichni pracovníci'),
                    ),
                    ..._workers.map(
                      (w) => DropdownMenuItem<String?>(
                        value: w['id'] as String,
                        child: Text(w['displayName'] as String? ?? w['username'] as String),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterWorkerId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _filterStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: _statusOptions.entries
                      .map(
                        (e) => DropdownMenuItem<String?>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _filterStatus = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _filterSystem,
                  decoration: const InputDecoration(
                    labelText: 'Systém',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Všechny systémy'),
                    ),
                    ...sealSystems.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s,
                        child: Text(s),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterSystem = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _filterEntryType,
                  decoration: const InputDecoration(
                    labelText: 'Typ prostupu',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Všechny typy'),
                    ),
                    ...entryTypes.map(
                      (t) => DropdownMenuItem<String?>(
                        value: t,
                        child: Text(t),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterEntryType = v),
                ),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: const Text('Export PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      return ListTile(
                        title: Text('${r['stavba']} | #${r['cisloUcpavky']}'),
                        subtitle: Text('${r['typProstupu']} – ${r['kusy']} ks'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
