import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import 'jobs_cache_service.dart';

class JobNumberScreen extends ConsumerStatefulWidget {
  const JobNumberScreen({super.key});

  @override
  ConsumerState<JobNumberScreen> createState() => _JobNumberScreenState();
}

class _JobNumberScreenState extends ConsumerState<JobNumberScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _offline = false;
  String? _error;

  Future<void> _open() async {
    if (_ctrl.text.length != 8) {
      setState(() => _error = 'Zadejte 8místné číslo stavby');
      return;
    }
    final userId = ref.read(currentUserIdProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
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
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) {
        await JobsCacheService(db).saveLastOpened(
          userId: userId,
          jobId: job['id'] as String,
        );
      }
      if (mounted) context.push('/floors/${job['id']}');
    } catch (_) {
      final cache = JobsCacheService(ref.read(databaseProvider));
      if (userId == null) {
        setState(() => _error = 'Stavba s tímto číslem neexistuje');
      } else {
        final job = await cache.findJobByProjectNumber(
          _ctrl.text,
          userId: userId,
        );
        if (job != null && mounted) {
          await cache.saveLastOpened(userId: userId, jobId: job['id'] as String);
          setState(() {
            _offline = true;
            _error = null;
          });
          if (mounted) context.push('/floors/${job['id']}');
        } else {
          setState(() => _error = 'Stavba s tímto číslem neexistuje');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Číslo stavby'),
        actions: [
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(compact: true)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Otevřít stavbu',
              subtitle: 'Zadejte 8místné číslo projektu',
              style: SectionHeaderStyle.h3,
            ),
            AppTextField(
              controller: _ctrl,
              label: '8místné číslo stavby',
              hint: '12345678',
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              prefixIcon: const Icon(Icons.numbers),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Otevřít stavbu',
              loading: _loading,
              onPressed: _open,
            ),
          ],
        ),
      ),
    );
  }
}
