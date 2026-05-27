import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ref.read(dioProvider).get('/api/reports/work-summary');
    setState(() {
      _rows = ((res.data as Map)['rows'] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  String get _csvUrl => '${AppConfig.apiBaseUrl}/api/reports/export/csv';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soupis prací')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ElevatedButton(onPressed: _load, child: const Text('Načíst')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('CSV: $_csvUrl (s auth header v prohlížeči)')),
                  ),
                  child: const Text('Export CSV'),
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
