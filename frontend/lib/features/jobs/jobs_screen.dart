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

/// Sloučená obrazovka: otevření stavby číslem + seznam zakázek.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  final _numberCtrl = TextEditingController();
  List<Map<String, dynamic>> _jobs = [];
  bool _loadingJobs = true;
  bool _loadingNumber = false;
  bool _offline = false;
  String? _numberError;
  String? _jobsError;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  bool get _showsAllJobs {
    final role = ref.watch(authUserProvider)?['role'] as String?;
    return role == 'vedeni' || role == 'ucetni' || role == 'admin';
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loadingJobs = true;
      _jobsError = null;
      _offline = false;
    });
    final userId = ref.read(currentUserIdProvider);
    final cache = JobsCacheService(ref.read(databaseProvider));
    try {
      final res = await ref.read(dioProvider).get('/api/jobs/my');
      final jobs = (res.data as List).cast<Map<String, dynamic>>();
      if (userId != null) {
        await cache.cacheMyJobsFromApi(jobs, userId);
      }
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loadingJobs = false;
      });
    } on DioException catch (_) {
      if (userId == null) {
        setState(() {
          _jobsError = 'Nepodařilo se načíst zakázky';
          _loadingJobs = false;
        });
        return;
      }
      final offline = await cache.loadMyJobsOffline(userId);
      if (!mounted) return;
      setState(() {
        _jobs = offline;
        _offline = true;
        _loadingJobs = false;
        _jobsError = offline.isEmpty ? 'Žádné uložené zakázky (offline)' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _jobsError = e.toString();
        _loadingJobs = false;
      });
    }
  }

  Future<bool> _openCachedByNumber(String userId) async {
    final cache = JobsCacheService(ref.read(databaseProvider));
    final job = await cache.findJobByProjectNumber(
      _numberCtrl.text,
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
      _numberError = null;
    });
    context.push('/floors/${job['id']}');
    return true;
  }

  Future<void> _openByNumber() async {
    if (_numberCtrl.text.length != 8) {
      setState(() => _numberError = 'Zadejte 8místné číslo stavby');
      return;
    }
    final userId = ref.read(currentUserIdProvider);
    setState(() {
      _loadingNumber = true;
      _numberError = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/api/jobs/by-number/${_numberCtrl.text}');
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
        final openedOffline = await _openCachedByNumber(userId);
        if (openedOffline) return;
      }
      if (mounted) setState(() => _numberError = jobNumberErrorMessage(e));
    } catch (_) {
      if (mounted) setState(() => _numberError = 'Stavbu se nepodařilo otevřít');
    } finally {
      if (mounted) setState(() => _loadingNumber = false);
    }
  }

  Future<void> _openJob(Map<String, dynamic> j) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId != null) {
      await JobsCacheService(ref.read(databaseProvider)).saveLastOpened(
        userId: userId,
        jobId: j['id'] as String,
        jobName: j['name'] as String?,
      );
    }
    if (!mounted) return;
    context.push('/floors/${j['id']}?jobId=${j['id']}');
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listTitle = _showsAllJobs ? 'Všechny zakázky' : 'Moje zakázky';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zakázky'),
        actions: [
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(compact: true)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SectionHeader(
              title: 'Otevřít stavbu',
              subtitle: 'Zadejte 8místné číslo projektu',
              style: SectionHeaderStyle.h3,
            ),
            AppTextField(
              key: const Key('job_number_input'),
              controller: _numberCtrl,
              label: '8místné číslo stavby',
              hint: '12345678',
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              prefixIcon: const Icon(Icons.numbers),
            ),
            if (_numberError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _numberError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            AppPrimaryButton(
              key: const Key('job_number_submit'),
              label: 'Otevřít stavbu',
              loading: _loadingNumber,
              onPressed: _openByNumber,
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: listTitle,
              style: SectionHeaderStyle.h3,
            ),
            if (_loadingJobs)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_jobsError != null)
              EmptyState(message: _jobsError!, icon: Icons.error_outline)
            else if (_jobs.isEmpty)
              const EmptyState(
                message: 'Zatím žádné zakázky',
                icon: Icons.work_outline,
              )
            else ...[
              if (_offline)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_off, color: AppColors.warning, size: 20),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Offline režim — data nemusí být aktuální',
                          style: TextStyle(color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ..._jobs.map((j) {
                final subtitle = _showsAllJobs
                    ? '${j['projectNumber']}'
                    : '${j['projectNumber']} · ${j['roleOnJob'] ?? 'worker'}';
                return AppCard(
                  leading: AppIconBox(
                    icon: Icons.apartment,
                    backgroundColor: AppColors.bgSecondary,
                    color: AppColors.textSecondary,
                  ),
                  title: j['name'] as String? ?? '',
                  subtitle: subtitle,
                  onTap: () => _openJob(j),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
