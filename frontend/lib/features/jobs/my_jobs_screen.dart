import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import 'jobs_cache_service.dart';

class MyJobsScreen extends ConsumerStatefulWidget {
  const MyJobsScreen({super.key});

  @override
  ConsumerState<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends ConsumerState<MyJobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  bool _offline = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
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
        _loading = false;
      });
    } on DioException catch (_) {
      if (userId == null) {
        setState(() {
          _error = 'Nepodařilo se načíst zakázky';
          _loading = false;
        });
        return;
      }
      final offline = await cache.loadMyJobsOffline(userId);
      if (!mounted) return;
      setState(() {
        _jobs = offline;
        _offline = true;
        _loading = false;
        _error = offline.isEmpty ? 'Žádné uložené zakázky (offline)' : null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openJob(Map<String, dynamic> j) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId != null) {
      await JobsCacheService(ref.read(databaseProvider)).saveLastOpened(
        userId: userId,
        jobId: j['id'] as String,
      );
    }
    if (!mounted) return;
    context.push('/floors/${j['id']}?jobId=${j['id']}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moje zakázky'),
        actions: [
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(label: 'Offline data', compact: true)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(message: _error!, icon: Icons.error_outline)
              : _jobs.isEmpty
                  ? const EmptyState(message: 'Zatím žádné zakázky', icon: Icons.work_outline)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: _jobs.length + (_offline ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (_offline && i == 0) {
                            return Container(
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
                            );
                          }
                          final idx = _offline ? i - 1 : i;
                          final j = _jobs[idx];
                          return AppCard(
                            leading: AppIconBox(
                              icon: Icons.apartment,
                              backgroundColor: AppColors.bgSecondary,
                              color: AppColors.textSecondary,
                            ),
                            title: j['name'] as String? ?? '',
                            subtitle:
                                '${j['projectNumber']} · ${j['roleOnJob'] ?? 'worker'}',
                            onTap: () => _openJob(j),
                          );
                        },
                      ),
                    ),
    );
  }
}
