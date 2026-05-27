import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';

class FloorListScreen extends ConsumerStatefulWidget {
  const FloorListScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<FloorListScreen> createState() => _FloorListScreenState();
}

class _FloorListScreenState extends ConsumerState<FloorListScreen> {
  List<Map<String, dynamic>> _floors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(dioProvider).get('/api/jobs/${widget.jobId}/floors');
    setState(() {
      _floors = (res.data as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Výběr patra')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _floors.length,
              itemBuilder: (_, i) {
                final f = _floors[i];
                return ListTile(
                  title: Text(f['name'] as String, style: const TextStyle(fontSize: 20)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/seals/${f['id']}?jobId=${widget.jobId}'),
                );
              },
            ),
    );
  }
}
