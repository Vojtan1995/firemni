import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/jobs/jobs_cache_service.dart';

void main() {
  test('cached jobs survive database reopen', () async {
    final db = AppDatabase.forTesting();
    final cache = JobsCacheService(db);
    await cache.cacheMyJobsFromApi([
      {
        'id': 'job-1',
        'projectNumber': '12345678',
        'name': 'Test stavba',
        'address': 'Praha',
        'isArchived': false,
        'roleOnJob': 'worker',
        'floors': [
          {'id': 'floor-1', 'name': '1. NP', 'sortOrder': 0},
        ],
      },
    ], 'user-1');

    final offline = await cache.loadMyJobsOffline('user-1');
    expect(offline, hasLength(1));
    expect(offline.first['projectNumber'], '12345678');

    final byNumber = await cache.findJobByProjectNumber(
      '12345678',
      userId: 'user-1',
    );
    expect(byNumber?['id'], 'job-1');
    expect(byNumber?['floors'], hasLength(1));

    expect(
      await cache.findJobByProjectNumber('12345678', userId: 'other-user'),
      isNull,
    );

    await db.close();
  });

  test('job opened by number is immediately available offline', () async {
    final db = AppDatabase.forTesting();
    final cache = JobsCacheService(db);
    final updatedAt = DateTime.utc(2026, 6, 11).toIso8601String();

    await cache.cacheOpenedJobFromApi(
      {
        'id': 'job-opened',
        'projectNumber': '87654321',
        'name': 'Nově otevřená stavba',
        'address': 'Brno',
        'status': 'active',
        'isArchived': false,
        'updatedAt': updatedAt,
        'floors': [
          {
            'id': 'floor-opened',
            'name': 'Přízemí',
            'sortOrder': 0,
            'updatedAt': updatedAt,
          },
        ],
      },
      userId: 'new-worker',
      roleOnJob: 'worker',
    );

    final offline = await cache.findJobByProjectNumber(
      '87654321',
      userId: 'new-worker',
    );
    expect(offline?['id'], 'job-opened');
    expect(offline?['floors'], hasLength(1));

    await db.close();
  });
}
