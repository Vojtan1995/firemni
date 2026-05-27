import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';

class JobNumberScreen extends ConsumerStatefulWidget {
  const JobNumberScreen({super.key});

  @override
  ConsumerState<JobNumberScreen> createState() => _JobNumberScreenState();
}

class _JobNumberScreenState extends ConsumerState<JobNumberScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _open() async {
    if (_ctrl.text.length != 8) {
      setState(() => _error = 'Zadejte 8místné číslo stavby');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/api/jobs/by-number/${_ctrl.text}');
      final job = res.data as Map<String, dynamic>;
      final db = ref.read(databaseProvider);
      await db.into(db.localJobs).insertOnConflictUpdate(
        LocalJobsCompanion.insert(
          id: job['id'] as String,
          projectNumber: job['projectNumber'] as String,
          name: job['name'] as String,
          address: Value(job['address'] as String?),
          isArchived: Value(job['isArchived'] as bool? ?? false),
          updatedAt: DateTime.parse(job['updatedAt'] as String),
        ),
      );
      for (final f in (job['floors'] as List? ?? [])) {
        final m = f as Map<String, dynamic>;
        await db.into(db.localFloors).insertOnConflictUpdate(
          LocalFloorsCompanion.insert(
            id: m['id'] as String,
            jobId: job['id'] as String,
            name: m['name'] as String,
            sortOrder: Value(m['sortOrder'] as int? ?? 0),
            updatedAt: DateTime.parse(m['updatedAt'] as String),
          ),
        );
      }
      if (mounted) context.push('/floors/${job['id']}');
    } catch (_) {
      setState(() => _error = 'Stavba s tímto číslem neexistuje');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Číslo stavby')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: '8místné číslo stavby',
                border: OutlineInputBorder(),
                hintText: '12345678',
              ),
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _open,
              child: _loading ? const CircularProgressIndicator() : const Text('Otevřít stavbu'),
            ),
          ],
        ),
      ),
    );
  }
}
