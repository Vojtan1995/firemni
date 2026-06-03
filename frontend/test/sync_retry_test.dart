import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/sync/sync_retry.dart';

/// FE-06: retry intervaly a stav outboxu dle docs/SYNC.md.
void main() {
  test('retry delays follow 30s, 2min, 5min schedule', () {
    expect(syncRetryDelayForCount(1), const Duration(seconds: 30));
    expect(syncRetryDelayForCount(2), const Duration(minutes: 2));
    expect(syncRetryDelayForCount(3), const Duration(minutes: 5));
    expect(syncRetryDelayForCount(10), const Duration(minutes: 5));
  });

  test('pushResultGapIndices marks tail when server returns fewer results (T3)', () {
    expect(pushResultGapIndices(5, 5), isEmpty);
    expect(pushResultGapIndices(5, 3), [3, 4]);
    expect(pushResultGapIndices(1, 0), [0]);
  });

  test('pending row is due for retry immediately when nextRetryAt is null',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-pending',
            mutationId: 'mut',
            userId: const Value('user-1'),
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('pending'),
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.localOutbox)
          ..where((o) => o.id.equals('out-pending')))
        .getSingle();
    expect(outboxIsDueForRetry(row, DateTime.now()), isTrue);
  });

  test('failed row waits until nextRetryAt', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 5, 27, 12, 0);
    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-failed',
            mutationId: 'mut',
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('failed'),
            retryCount: const Value(1),
            nextRetryAt: Value(now.add(const Duration(minutes: 5))),
            createdAt: now,
          ),
        );
    final row = await (db.select(db.localOutbox)
          ..where((o) => o.id.equals('out-failed')))
        .getSingle();
    expect(
        outboxIsDueForRetry(row, now.add(const Duration(minutes: 1))), isFalse);
    expect(
        outboxIsDueForRetry(row, now.add(const Duration(minutes: 5))), isTrue);
  });

  test('conflict row is never due for automatic retry', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-conflict',
            mutationId: 'mut',
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('conflict'),
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.localOutbox)
          ..where((o) => o.id.equals('out-conflict')))
        .getSingle();
    expect(outboxIsDueForRetry(row, DateTime.now()), isFalse);
  });

  test('markOutboxSyncFailure increments retry_count and stores last_error',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 5, 27, 10, 0);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-1',
            mutationId: 'mut-1',
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('pending'),
            retryCount: const Value(0),
            createdAt: now,
          ),
        );

    await markOutboxSyncFailure(
      db,
      'out-1',
      currentRetryCount: 0,
      error: 'network error',
      now: now,
    );

    final row = await (db.select(db.localOutbox)
          ..where((o) => o.id.equals('out-1')))
        .getSingle();
    expect(row.status, 'failed');
    expect(row.retryCount, 1);
    expect(row.lastError, 'network error');
    expect(row.nextRetryAt, syncNextRetryAt(1, now));
  });

  test('markOutboxSyncSuccess resets retry state', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-2',
            mutationId: 'mut-2',
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('failed'),
            retryCount: const Value(3),
            lastError: const Value('old'),
            nextRetryAt: Value(DateTime.now().add(const Duration(minutes: 5))),
            createdAt: DateTime.now(),
          ),
        );

    await markOutboxSyncSuccess(db, 'out-2');

    final row = await (db.select(db.localOutbox)
          ..where((o) => o.id.equals('out-2')))
        .getSingle();
    expect(row.status, 'done');
    expect(row.retryCount, 0);
    expect(row.lastError, isNull);
    expect(row.nextRetryAt, isNull);
  });

  test(
      'markPhotoSyncSuccess stores serverPath when upload returns file metadata',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'photo-1',
            sealId: 'seal-1',
            localPath: 'local.webp',
            status: const Value('failed'),
            retryCount: const Value(2),
            lastError: const Value('old upload error'),
            nextRetryAt: Value(DateTime.now().add(const Duration(minutes: 5))),
            createdAt: DateTime.now(),
          ),
        );

    await markPhotoSyncSuccess(db, 'photo-1', serverPath: 'server-photo.webp');

    final row = await (db.select(db.localPhotos)
          ..where((p) => p.id.equals('photo-1')))
        .getSingle();
    expect(row.status, 'done');
    expect(row.retryCount, 0);
    expect(row.lastError, isNull);
    expect(row.nextRetryAt, isNull);
    expect(row.serverPath, 'server-photo.webp');
  });

  test('markPhotoSyncSuccess replaces local id with server photo id', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'local-photo-id',
            sealId: 'seal-1',
            localPath: '/data/seal_photos/local.webp',
            status: const Value('pending'),
            createdAt: DateTime.now(),
          ),
        );

    await markPhotoSyncSuccess(
      db,
      'local-photo-id',
      serverPath: 'server.webp',
      serverPhotoId: 'server-photo-id',
    );

    final oldRow = await (db.select(db.localPhotos)
          ..where((p) => p.id.equals('local-photo-id')))
        .getSingleOrNull();
    expect(oldRow, isNull);

    final newRow = await (db.select(db.localPhotos)
          ..where((p) => p.id.equals('server-photo-id')))
        .getSingle();
    expect(newRow.status, 'done');
    expect(newRow.serverPath, 'server.webp');
    expect(newRow.localPath, '/data/seal_photos/local.webp');
  });

  test('countDueSyncItems excludes failed rows before nextRetryAt (T4)', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 5, 27, 10, 0);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-due',
            mutationId: 'mut-due',
            userId: const Value('user-1'),
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('pending'),
            createdAt: now,
          ),
        );
    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-wait',
            mutationId: 'mut-wait',
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('failed'),
            retryCount: const Value(1),
            nextRetryAt: Value(now.add(const Duration(minutes: 5))),
            createdAt: now,
          ),
        );

    expect(await countDueSyncItems(db, now, userId: 'user-1'), 1);
  });

  test('countUnsentPhotos counts pending and failed rows', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 5, 27, 10, 0);

    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'photo-pending',
            sealId: 'seal-1',
            localPath: 'local.webp',
            status: const Value('pending'),
            createdAt: now,
          ),
        );
    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'photo-failed',
            sealId: 'seal-1',
            localPath: 'local2.webp',
            status: const Value('failed'),
            createdAt: now,
          ),
        );
    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'photo-done',
            sealId: 'seal-1',
            localPath: 'local3.webp',
            status: const Value('done'),
            createdAt: now,
          ),
        );

    expect(await countUnsentPhotos(db), 2);
  });

  test('countDueSyncItems skips photos blocked by unsynced seal (T5)', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 5, 27, 10, 0);

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-local',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '1',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            isSynced: const Value(false),
            updatedAt: now,
          ),
        );
    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'photo-1',
            sealId: 'seal-local',
            localPath: 'local.webp',
            status: const Value('pending'),
            createdAt: now,
          ),
        );

    expect(await countDueSyncItems(db, now), 0);
    expect(isPhotoUploadBlockedBySeal(
      await (db.select(db.localSeals)..where((s) => s.id.equals('seal-local')))
          .getSingle(),
    ), isTrue);
  });

  test('hasDueSyncWork ignores failed outbox before nextRetryAt', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 5, 27, 10, 0);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-3',
            mutationId: 'mut-3',
            userId: const Value('user-1'),
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('failed'),
            retryCount: const Value(1),
            nextRetryAt: Value(now.add(const Duration(minutes: 2))),
            createdAt: now,
          ),
        );

    expect(await hasDueSyncWork(db, now, userId: 'user-1'), isFalse);
    expect(
        await hasDueSyncWork(db, now.add(const Duration(minutes: 2)),
            userId: 'user-1'),
        isTrue);
  });
}
