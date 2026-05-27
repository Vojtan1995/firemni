import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';

class JobsAdminScreen extends ConsumerStatefulWidget {
  const JobsAdminScreen({super.key});

  @override
  ConsumerState<JobsAdminScreen> createState() => _JobsAdminScreenState();
}

class _JobsAdminScreenState extends ConsumerState<JobsAdminScreen> {
  List<Map<String, dynamic>> _jobs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(dioProvider).get('/api/jobs', queryParameters: {'archived': 'false'});
    setState(() => _jobs = (res.data as List).cast<Map<String, dynamic>>());
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
    await ref.read(dioProvider).post('/api/jobs', data: {
      'projectNumber': numCtrl.text,
      'name': nameCtrl.text,
    });
    await _load();
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
    await ref.read(dioProvider).post('/api/jobs/$jobId/floors', data: {'name': nameCtrl.text});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stavby')),
      floatingActionButton: FloatingActionButton(onPressed: _createJob, child: const Icon(Icons.add)),
      body: ListView.builder(
        itemCount: _jobs.length,
        itemBuilder: (_, i) {
          final j = _jobs[i];
          final floors = (j['floors'] as List?) ?? [];
          return ExpansionTile(
            title: Text('${j['projectNumber']} – ${j['name']}'),
            children: [
              ...floors.map((f) => ListTile(title: Text((f as Map)['name'] as String))),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Přidat patro'),
                onTap: () => _addFloor(j['id'] as String),
              ),
            ],
          );
        },
      ),
    );
  }
}
