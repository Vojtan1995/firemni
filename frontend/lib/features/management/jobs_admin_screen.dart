import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

class JobsAdminScreen extends ConsumerStatefulWidget {
  const JobsAdminScreen({super.key});

  @override
  ConsumerState<JobsAdminScreen> createState() => _JobsAdminScreenState();
}

class _JobsAdminScreenState extends ConsumerState<JobsAdminScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showError(Object e) {
    String msg = e.toString();
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        msg = data['error'] as String;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get(
        '/api/jobs',
        queryParameters: {'archived': _showArchived ? 'true' : 'false'},
      );
      setState(() => _jobs = (res.data as List).cast<Map<String, dynamic>>());
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _createJob() async {
    final numCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nová stavba'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: numCtrl, decoration: const InputDecoration(labelText: '8místné číslo')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Název')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vytvořit')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).post('/api/jobs', data: {
        'projectNumber': numCtrl.text,
        'name': nameCtrl.text,
      });
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _editJob(Map<String, dynamic> job) async {
    final nameCtrl = TextEditingController(text: job['name'] as String? ?? '');
    final addressCtrl = TextEditingController(text: job['address'] as String? ?? '');
    final noteCtrl = TextEditingController(text: job['note'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Upravit ${job['projectNumber']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Název')),
              TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Adresa')),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Poznámka')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Uložit')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).patch('/api/jobs/${job['id']}', data: {
        'name': nameCtrl.text,
        'address': addressCtrl.text.isEmpty ? null : addressCtrl.text,
        'note': noteCtrl.text.isEmpty ? null : noteCtrl.text,
      });
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Smazat stavbu?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Důvod (volitelně)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Smazat')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).delete(
        '/api/jobs/${job['id']}',
        data: reasonCtrl.text.isEmpty ? {} : {'deleteReason': reasonCtrl.text},
      );
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _setArchived(Map<String, dynamic> job, bool archived) async {
    try {
      final path = archived ? 'archive' : 'unarchive';
      await ref.read(dioProvider).patch('/api/jobs/${job['id']}/$path');
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _addFloor(String jobId) async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nové patro'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Název patra')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Přidat')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).post('/api/jobs/$jobId/floors', data: {'name': nameCtrl.text});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _editFloor(String jobId, Map<String, dynamic> floor) async {
    final nameCtrl = TextEditingController(text: floor['name'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Upravit patro'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Název patra')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Uložit')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).patch('/api/jobs/$jobId/floors/${floor['id']}', data: {
        'name': nameCtrl.text,
      });
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteFloor(String jobId, Map<String, dynamic> floor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Smazat patro?'),
        content: Text('Opravdu smazat patro „${floor['name']}“?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Smazat')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).delete('/api/jobs/$jobId/floors/${floor['id']}');
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stavby'),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined),
            tooltip: _showArchived ? 'Aktivní stavby' : 'Archiv',
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton(onPressed: _createJob, child: const Icon(Icons.add)),
      body: _jobs.isEmpty
          ? EmptyState(
              message: _showArchived ? 'Žádné archivované stavby' : 'Žádné aktivní stavby',
              icon: Icons.apartment_outlined,
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _jobs.length,
              itemBuilder: (_, i) {
                final j = _jobs[i];
                final jobId = j['id'] as String;
                final floors = (j['floors'] as List?) ?? [];
                final isArchived = j['isArchived'] == true;
                return AppCard(
                  showChevron: false,
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: AppColors.border,
                    ),
                    child: ExpansionTile(
                      leading: AppIconBox(
                        icon: isArchived ? Icons.inventory_2 : Icons.apartment,
                      ),
                      title: Text(
                        '${j['projectNumber']} – ${j['name']}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      subtitle: isArchived
                          ? Text(
                              'Archivováno',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                            )
                          : null,
                      children: [
                        if (_showArchived)
                          ListTile(
                            leading: const Icon(Icons.unarchive),
                            title: const Text('Obnovit z archivu'),
                            onTap: () => _setArchived(j, false),
                          )
                        else ...[
                          ListTile(
                            leading: const Icon(Icons.edit),
                            title: const Text('Upravit stavbu'),
                            onTap: () => _editJob(j),
                          ),
                          ListTile(
                            leading: const Icon(Icons.archive),
                            title: const Text('Archivovat'),
                            onTap: () => _setArchived(j, true),
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete_outline),
                            title: const Text('Smazat stavbu'),
                            onTap: () => _deleteJob(j),
                          ),
                        ],
                        ...floors.map((f) {
                          final floor = f as Map<String, dynamic>;
                          return ListTile(
                            title: Text(floor['name'] as String),
                            trailing: _showArchived
                                ? null
                                : PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _editFloor(jobId, floor);
                                      if (v == 'delete') _deleteFloor(jobId, floor);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Upravit')),
                                      PopupMenuItem(value: 'delete', child: Text('Smazat')),
                                    ],
                                  ),
                          );
                        }),
                        if (!_showArchived)
                          ListTile(
                            leading: const Icon(Icons.add),
                            title: const Text('Přidat patro'),
                            onTap: () => _addFloor(jobId),
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
