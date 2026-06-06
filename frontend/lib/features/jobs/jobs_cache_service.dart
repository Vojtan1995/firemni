import 'package:drift/drift.dart';
import '../../database/database.dart';

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
      await db.into(db.localJobs).insertOnConflictUpdate(
            LocalJobsCompanion.insert(
              id: jobId,
              projectNumber: j['projectNumber'] as String,
              name: j['name'] as String,
              address: Value(j['address'] as String?),
              isArchived: Value(isArchived),
              status: Value(isArchived ? 'archived' : 'active'),
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

  Future<Map<String, dynamic>?> findJobByProjectNumber(String number) async {
    final job = await (db.select(db.localJobs)
          ..where((j) =>
              j.projectNumber.equals(number) & j.deletedAt.isNull()))
        .getSingleOrNull();
    if (job == null) return null;

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

  Future<void> _setPref(String key, String value) async {
    await db.into(db.localUserPrefs).insertOnConflictUpdate(
          LocalUserPrefsCompanion.insert(key: key, value: value),
        );
  }

  Future<String?> _getPref(String key) async {
    final row = await (db.select(db.localUserPrefs)
          ..where((p) => p.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> saveLastOpened({
    required String userId,
    required String jobId,
    String? floorId,
  }) async {
    final now = DateTime.now();
    await _setPref('last_job_id_$userId', jobId);
    if (floorId != null) {
      await _setPref('last_floor_id_$userId', floorId);
    }
    await _setPref('last_opened_at_$userId', now.toIso8601String());

    await (db.update(db.localMyJobAssignments)
          ..where((a) => a.userId.equals(userId) & a.jobId.equals(jobId)))
        .write(LocalMyJobAssignmentsCompanion(lastActivityAt: Value(now)));
  }

  Future<({String? jobId, String? floorId, String? jobName})> loadLastOpened(
    String userId,
  ) async {
    final jobId = await _getPref('last_job_id_$userId');
    final floorId = await _getPref('last_floor_id_$userId');
    String? jobName;
    if (jobId != null) {
      final job = await (db.select(db.localJobs)
            ..where((j) => j.id.equals(jobId)))
          .getSingleOrNull();
      jobName = job?.name;
    }
    return (jobId: jobId, floorId: floorId, jobName: jobName);
  }
}
