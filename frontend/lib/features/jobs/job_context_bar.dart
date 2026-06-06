import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../database/database_provider.dart';

class JobContextInfo {
  const JobContextInfo({
    required this.projectNumber,
    required this.name,
    this.address,
  });

  final String projectNumber;
  final String name;
  final String? address;
}

final jobContextProvider =
    FutureProvider.family<JobContextInfo?, String>((ref, jobId) async {
  if (jobId.isEmpty) return null;

  final db = ref.read(databaseProvider);
  final local = await (db.select(db.localJobs)..where((j) => j.id.equals(jobId)))
      .getSingleOrNull();
  if (local != null) {
    return JobContextInfo(
      projectNumber: local.projectNumber,
      name: local.name,
      address: local.address,
    );
  }

  final dio = ref.read(dioProvider);
  for (final path in ['/api/jobs/my', '/api/jobs']) {
    try {
      final res = await dio.get(path);
      final list = (res.data as List).cast<Map<String, dynamic>>();
      final found = list.where((j) => j['id'] == jobId).firstOrNull;
      if (found != null) {
        return JobContextInfo(
          projectNumber: found['projectNumber'] as String? ?? '',
          name: found['name'] as String? ?? '',
          address: found['address'] as String?,
        );
      }
    } catch (_) {}
  }
  return null;
});

class JobContextBar extends ConsumerWidget {
  const JobContextBar({
    super.key,
    required this.jobId,
    this.floorName,
  });

  final String jobId;
  final String? floorName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (jobId.isEmpty) return const SizedBox.shrink();

    final asyncInfo = ref.watch(jobContextProvider(jobId));

    return asyncInfo.when(
      data: (info) {
        if (info == null) return const SizedBox.shrink();
        final parts = <String>[
          'Zakázky',
          '${info.projectNumber} ${info.name}'.trim(),
        ];
        if (floorName != null && floorName!.isNotEmpty) parts.add(floorName!);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  parts.join(' → '),
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 32),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
