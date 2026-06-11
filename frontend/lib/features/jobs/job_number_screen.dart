import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import 'job_number_errors.dart';
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

  Future<bool> _openCachedJob(String userId) async {
    final cache = JobsCacheService(ref.read(databaseProvider));
    final job = await cache.findJobByProjectNumber(
      _ctrl.text,
      userId: userId,
    );
    if (job == null || !mounted) return false;

    await cache.saveLastOpened(
      userId: userId,
      jobId: job['id'] as String,
      jobName: job['name'] as String?,
    );
    if (!mounted) return false;
    setState(() {
      _offline = true;
      _error = null;
    });
    context.push('/floors/${job['id']}');
    return true;
  }

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
      if (userId != null) {
        final role = ref.read(authUserProvider)?['role'] as String?;
        await JobsCacheService(db).cacheOpenedJobFromApi(
          job,
          userId: userId,
          roleOnJob: role == 'worker' ? 'worker' : 'viewer',
        );
        await JobsCacheService(db).saveLastOpened(
          userId: userId,
          jobId: job['id'] as String,
          jobName: job['name'] as String?,
        );
      }
      if (mounted) context.push('/floors/${job['id']}');
    } on DioException catch (e) {
      if (userId != null && shouldTryOfflineJobCache(e)) {
        final openedOffline = await _openCachedJob(userId);
        if (openedOffline) return;
      }
      if (mounted) setState(() => _error = jobNumberErrorMessage(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Stavbu se nepodařilo otevřít');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
              key: const Key('job_number_input'),
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
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              key: const Key('job_number_submit'),
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
