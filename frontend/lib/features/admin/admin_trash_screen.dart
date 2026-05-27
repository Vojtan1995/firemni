import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';

class AdminTrashScreen extends ConsumerStatefulWidget {
  const AdminTrashScreen({super.key});

  @override
  ConsumerState<AdminTrashScreen> createState() => _AdminTrashScreenState();
}

class _AdminTrashScreenState extends ConsumerState<AdminTrashScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final _dateFormat = DateFormat('d.M.y HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).get('/api/seals/trash');
      if (!mounted) return;
      setState(() {
        _items = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFromDio(e, 'Nepodařilo se načíst koš');
      });
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final sealNumber = item['sealNumber'] as String? ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Obnovit ucpávku'),
        content: Text('Obnovit ucpávku č. $sealNumber?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Obnovit')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref.read(dioProvider).patch('/api/seals/${item['id']}/restore');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ucpávka č. $sealNumber byla obnovena')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageFromDio(e, 'Obnovení selhalo')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String _messageFromDio(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return fallback;
  }

  String _formatDeletedAt(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return _dateFormat.format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Koš / Smazané položky'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _load, child: const Text('Zkusit znovu')),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('Koš je prázdný.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final entityType = item['entityType'] as String? ?? 'seal';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Typ: $entityType · Ucpávka #${item['sealNumber']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text('Stavba: ${item['stavba']} – ${item['nazevStavby']}'),
                                Text('Patro: ${item['patro']}'),
                                Text('Smazal: ${item['deletedByName'] ?? '—'}'),
                                Text('Smazáno: ${_formatDeletedAt(item['deletedAt'])}'),
                                if (item['deleteReason'] != null &&
                                    (item['deleteReason'] as String).isNotEmpty)
                                  Text('Důvod: ${item['deleteReason']}'),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _restore(item),
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Obnovit'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
