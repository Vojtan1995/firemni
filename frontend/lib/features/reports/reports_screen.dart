import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/api/api_client.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = false;
  bool _exporting = false;
  String? _filterJobId;
  String? _filterStatus;

  static const _statusOptions = <String?, String>{
    null: 'Všechny statusy',
    'draft': 'Koncept',
    'checked': 'Zkontrolováno',
    'invoiced': 'Vyfakturováno',
  };

  Map<String, String> get _queryParams {
    final params = <String, String>{};
    if (_filterJobId != null && _filterJobId!.isNotEmpty) {
      params['jobId'] = _filterJobId!;
    }
    if (_filterStatus != null && _filterStatus!.isNotEmpty) {
      params['status'] = _filterStatus!;
    }
    return params;
  }

  @override
  void initState() {
    super.initState();
    _loadJobs();
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get(
        '/api/reports/work-summary',
        queryParameters: _queryParams,
      );
      if (!mounted) return;
      setState(() {
        _rows = ((res.data as Map)['rows'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(_dioMessage(e, 'Nepodařilo se načíst soupis'));
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final res = await ref.read(dioProvider).get(
        '/api/reports/export/csv',
        queryParameters: _queryParams,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Export vrátil prázdný soubor');
      }

      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final filePath = p.join(dir.path, 'soupis_praci_$date.csv');
      await File(filePath).writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV uloženo: $filePath')),
      );
    } on DioException catch (e) {
      _showError(_dioMessage(e, 'Export CSV selhal'));
    } catch (e) {
      _showError('Export CSV selhal: $e');
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
                  onChanged: (v) => setState(() => _filterJobId = v),
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
                Row(
                  children: [
                    Expanded(
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
                    const SizedBox(width: 8),
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
