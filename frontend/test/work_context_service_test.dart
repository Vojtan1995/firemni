import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/jobs/work_context_service.dart';

void main() {
  test('saves and loads job/floor/seal context', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    const userId = 'user-1';

    await db.into(db.localJobs).insert(
          LocalJobsCompanion.insert(
            id: 'job-1',
            projectNumber: '12345678',
            name: 'Demo stavba',
            updatedAt: DateTime.now(),
          ),
        );
    await db.into(db.localFloors).insert(
          LocalFloorsCompanion.insert(
            id: 'floor-1',
            jobId: 'job-1',
            name: '1. NP',
            updatedAt: DateTime.now(),
          ),
        );

    final service = WorkContextService(db);

    await service.saveJob(userId: userId, jobId: 'job-1', jobName: 'Demo stavba');
    var ctx = await service.load(userId);
    expect(ctx?.jobId, 'job-1');
    expect(ctx?.floorId, isNull);
    expect(ctx?.resumeSubtitle, contains('Demo stavba'));
    expect(service.resumeRoute(ctx!), '/floors/job-1');

    await service.saveFloor(
      userId: userId,
      jobId: 'job-1',
      floorId: 'floor-1',
      floorName: '1. NP',
    );
    ctx = await service.load(userId);
    expect(ctx?.floorId, 'floor-1');
    expect(service.resumeRoute(ctx!), '/seals/floor-1?jobId=job-1');

    await service.saveSeal(
      userId: userId,
      jobId: 'job-1',
      floorId: 'floor-1',
      sealId: 'seal-9',
    );
    ctx = await service.load(userId);
    expect(ctx?.sealId, 'seal-9');
    expect(service.resumeRoute(ctx!), '/seal/seal-9');
  });

  test('loads legacy prefs when JSON context missing', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    const userId = 'user-legacy';

    await db.into(db.localUserPrefs).insert(
          LocalUserPrefsCompanion.insert(
            key: 'last_job_id_$userId',
            value: 'job-old',
          ),
        );
    await db.into(db.localUserPrefs).insert(
          LocalUserPrefsCompanion.insert(
            key: 'last_floor_id_$userId',
            value: 'floor-old',
          ),
        );

    final ctx = await WorkContextService(db).load(userId);
    expect(ctx?.jobId, 'job-old');
    expect(ctx?.floorId, 'floor-old');
  });
}
