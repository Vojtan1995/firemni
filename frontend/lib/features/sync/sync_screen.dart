import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_service.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _syncing = false;
  String? _message;

  Future<void> _sync() async {
    setState(() { _syncing = true; _message = null; });
    final result = await ref.read(syncServiceProvider).syncAll();
    setState(() {
      _syncing = false;
      _message = result.offline ? 'Offline – data zůstávají lokálně' : 'Synchronizace dokončena';
    });
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(connectivityProvider);
    final pending = ref.watch(syncPendingCountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronizace')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  online.valueOrNull == true ? Icons.cloud_done : Icons.cloud_off,
                  color: online.valueOrNull == true ? Colors.green : Colors.orange,
                  size: 40,
                ),
                title: Text(online.valueOrNull == true ? 'Online' : 'Offline'),
                subtitle: Text('Čekajících položek: ${pending.valueOrNull ?? 0}'),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _syncing ? null : _sync,
              icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 28),
              label: const Text('Synchronizovat', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 64)),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
