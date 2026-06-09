import 'package:drift/drift.dart';
import '../../database/database.dart';
import 'work_context_service.dart';

class JobsCacheService {
  JobsCacheService(this.db);

  final AppDatabase db;

  Future<void> cacheMyJobsFromApi(
    List<Map<String, dynamic>> jobs,
    String userId,
  ) async {
    final now = DateTime.now();
    for (final j in jobs) {
      final jobId = j['id'] as String;
      final isArchived = j['isArchived'] as bool? ?? false;
      final status = j['status'] as String? ?? (isArchived ? 'archived' : 'active');
      await db.into(db.localJobs).insertOnConflictUpdate(
            LocalJobsCompanion.insert(
              id: jobId,
              projectNumber: j['projectNumber'] as String,
              name: j['name'] as String,
              address: Value(j['address'] as String?),
              isArchived: Value(isArchived),
              status: Value(status),
              lastSyncedAt: Value(now),
              updatedAt: now,
            ),
          );

      final floors = j['floors'] as List? ?? [];
      for (final f in floors) {
        final m = f as Map<String, dynamic>;
        await db.into(db.localFloors).insertOnConflictUpdate(
              LocalFloorsCompanion.insert(
                id: m['id'] as String,
                jobId: jobId,
                name: m['name'] as String,
                sortOrder: Value(m['sortOrder'] as int? ?? 0),
                updatedAt: now,
              ),
            );
      }

      await db.into(db.localMyJobAssignments).insertOnConflictUpdate(
            LocalMyJobAssignmentsCompanion.insert(
              userId: userId,
              jobId: jobId,
              roleOnJob: Value(j['roleOnJob'] as String? ?? 'worker'),
              lastActivityAt: now,
            ),
          );
    }

    final currentJobIds = jobs.map((j) => j['id'] as String).toSet();
    if (currentJobIds.isEmpty) {
      await (db.delete(db.localMyJobAssignments)
            ..where((a) => a.userId.equals(userId)))
          .go();
    } else {
      await (db.delete(db.localMyJobAssignments)
            ..where((a) =>
                a.userId.equals(userId) & a.jobId.isNotIn(currentJobIds.toList())))
          .go();
    }
  }

  Future<List<Map<String, dynamic>>> loadMyJobsOffline(String userId) async {
    final assignments = await (db.select(db.localMyJobAssignments)
          ..where((a) => a.userId.equals(userId))
          ..orderBy([(a) => OrderingTerm.desc(a.lastActivityAt)]))
        .get();

    final result = <Map<String, dynamic>>[];
    for (final a in assignments) {
      final job = await (db.select(db.localJobs)
            ..where((j) => j.id.equals(a.jobId)))
          .getSingleOrNull();
      if (job == null || job.deletedAt != null) continue;
      final status = job.status ?? (job.isArchived ? 'archived' : 'active');
      if (status != 'active') continue;

      final floors = await (db.select(db.localFloors)
            ..where((f) => f.jobId.equals(job.id) & f.deletedAt.isNull())
            ..orderBy([(f) => OrderingTerm.asc(f.sortOrder)]))
          .get();

      result.add({
        'id': job.id,
        'projectNumber': job.projectNumber,
        'name': job.name,
        'address': job.address,
        'isArchived': job.isArchived,
        'roleOnJob': a.roleOnJob,
        'lastSyncedAt': job.lastSyncedAt?.toIso8601String(),
        'floors': floors
            .map((f) => {
                  'id': f.id,
                  'name': f.name,
                  'sortOrder': f.sortOrder,
                })
            .toList(),
      });
    }
    return result;
  }

  Future<Map<String, dynamic>?> findJobByProjectNumber(
    String number, {
    required String userId,
  }) async {
    final job = await (db.select(db.localJobs)
          ..where((j) =>
              j.projectNumber.equals(number) &
              j.deletedAt.isNull() &
              (j.status.equals('active') | j.status.isNull())))
        .getSingleOrNull();
    if (job == null) return null;

    final assignment = await (db.select(db.localMyJobAssignments)
          ..where((a) => a.userId.equals(userId) & a.jobId.equals(job.id)))
        .getSingleOrNull();
    if (assignment == null) return null;

    final floors = await (db.select(db.localFloors)
          ..where((f) => f.jobId.equals(job.id) & f.deletedAt.isNull())
          ..orderBy([(f) => OrderingTerm.asc(f.sortOrder)]))
        .get();

    return {
      'id': job.id,
      'projectNumber': job.projectNumber,
      'name': job.name,
      'address': job.address,
      'floors': floors
          .map((f) => {
                'id': f.id,
                'name': f.name,
                'sortOrder': f.sortOrder,
              })
          .toList(),
    };
  }

  Future<void> saveLastOpened({
    required String userId,
    required String jobId,
    String? floorId,
    String? jobName,
    String? floorName,
  }) async {
    final work = WorkContextService(db);
    if (floorId != null) {
      await work.saveFloor(
        userId: userId,
        jobId: jobId,
        floorId: floorId,
        jobName: jobName,
        floorName: floorName,
      );
      return;
    }
    await work.saveJob(userId: userId, jobId: jobId, jobName: jobName);
  }

  Future<({String? jobId, String? floorId, String? jobName})> loadLastOpened(
    String userId,
  ) async {
    final ctx = await WorkContextService(db).load(userId);
    if (ctx == null) {
      return (jobId: null, floorId: null, jobName: null);
    }
    return (jobId: ctx.jobId, floorId: ctx.floorId, jobName: ctx.jobName);
  }

  Future<void> clearUserScopedCache(String userId) async {
    await (db.delete(db.localMyJobAssignments)
          ..where((a) => a.userId.equals(userId)))
        .go();
    await (db.delete(db.syncCursor)
          ..where((c) => c.key.equals('last_pull_$userId')))
        .go();
  }
}
