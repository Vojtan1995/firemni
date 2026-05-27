import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../database/database_provider.dart';
import 'sync_conflict.dart';
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
    setState(() {
      _syncing = true;
      _message = null;
    });
    final result = await ref.read(syncServiceProvider).syncAll();
    setState(() {
      _syncing = false;
      _message = result.offline ? 'Offline – data zůstávají lokálně' : 'Synchronizace dokončena';
    });
  }

  Future<void> _dismissConflict(String outboxId) async {
    final db = ref.read(databaseProvider);
    await dismissSyncConflict(db, outboxId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upozornění skryto – lokální data zůstávají zachována')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(connectivityProvider);
    final pending = ref.watch(syncPendingCountProvider);
    final conflicts = ref.watch(syncConflictsProvider);
    final dateFormat = DateFormat('d.M.y HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronizace')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 28),
            label: const Text('Synchronizovat', style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 64)),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          Text(
            'Konflikty synchronizace',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          conflicts.when(
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => Text('Chyba načtení konfliktů: $e'),
            data: (items) {
              if (items.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline, color: Colors.green),
                    title: Text('Žádné aktivní konflikty'),
                    subtitle: Text('Lokální změny nejsou v konfliktu se serverem.'),
                  ),
                );
              }
              return Column(
                children: items.map((c) {
                  return Card(
                    color: Colors.orange.shade50,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${c.entityType} · ${c.operationLabel}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          if (c.sealNumber != null) ...[
                            const SizedBox(height: 8),
                            Text('Ucpávka č. ${c.sealNumber}'),
                          ],
                          if (c.jobLabel != null) Text('Stavba: ${c.jobLabel}'),
                          if (c.floorName != null) Text('Patro: ${c.floorName}'),
                          const SizedBox(height: 8),
                          Text('Důvod: ${c.conflictMessage}'),
                          const SizedBox(height: 4),
                          Text(
                            'Čas: ${dateFormat.format(c.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _dismissConflict(c.outboxId),
                              icon: const Icon(Icons.visibility_off),
                              label: const Text('Skrýt upozornění'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
