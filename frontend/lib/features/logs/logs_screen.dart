import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(dioProvider).get('/api/logs/activity');
    setState(() => _logs = (res.data as List).cast<Map<String, dynamic>>());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (_, i) {
          final l = _logs[i];
          final user = l['user'] as Map<String, dynamic>?;
          return ListTile(
            title: Text('${l['action']} – ${l['entityType'] ?? ''}'),
            subtitle: Text('${user?['displayName'] ?? ''} | ${l['createdAt']}'),
          );
        },
      ),
    );
  }
}
