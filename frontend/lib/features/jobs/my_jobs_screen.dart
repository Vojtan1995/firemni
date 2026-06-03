import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';

class MyJobsScreen extends ConsumerStatefulWidget {
  const MyJobsScreen({super.key});

  @override
  ConsumerState<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends ConsumerState<MyJobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String? _error;

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
      final res = await ref.read(dioProvider).get('/api/jobs/my');
      setState(() {
        _jobs = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e is DioException ? 'Nepodařilo se načíst zakázky' : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moje zakázky')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _jobs.isEmpty
                  ? const Center(child: Text('Zatím žádné zakázky'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _jobs.length,
                        itemBuilder: (_, i) {
                          final j = _jobs[i];
                          return ListTile(
                            leading: const Icon(Icons.apartment),
                            title: Text(j['name'] as String? ?? ''),
                            subtitle: Text(
                              '${j['projectNumber']} · ${j['roleOnJob'] ?? 'worker'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              final floors = j['floors'] as List?;
                              if (floors != null && floors.isNotEmpty) {
                                context.push(
                                  '/floors/${j['id']}?jobId=${j['id']}',
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}
