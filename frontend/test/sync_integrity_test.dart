import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/sync/sync_conflict.dart';
import 'package:ucpavky/features/sync/sync_retry.dart';

void main() {
  group('mergeSealListWithLocalRows', () {
    test('skips local row when sealNumber already in API list', () {
      final merged = mergeSealListWithLocalRows(
        apiList: [
          {
            'id': 'server-id',
            'sealNumber': '42',
            'status': 'draft',
          },
        ],
        localOnFloor: [
          LocalSeal(
            id: 'orphan-local-id',
            jobId: 'job',
            floorId: 'floor',
            sealNumber: '42',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            note: null,
            status: 'draft',
            version: 1,
            isSynced: true,
            syncConflict: false,
            markerPlacementPending: false,
            jsonPayload: null,
            deletedAt: null,
            updatedAt: DateTime.now(),
          ),
        ],
        mapLocal: (row) => {'id': row.id, 'sealNumber': row.sealNumber},
      );

      expect(merged.length, 1);
      expect(merged.first['id'], 'server-id');
    });
  });

  group('sealListCacheSyncFlags', () {
    test('preserves unsynced when active outbox exists', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      await db.into(db.localSeals).insert(
            LocalSealsCompanion.insert(
              id: 'seal-1',
              jobId: 'job-1',
              floorId: 'floor-1',
              sealNumber: '1',
              system: 'S',
              construction: 'C',
              location: 'L',
              fireRating: 'EI',
              isSynced: const Value(false),
              updatedAt: DateTime.now(),
            ),
          );
      await db.into(db.localOutbox).insert(
            LocalOutboxCompanion.insert(
              id: 'out-1',
              mutationId: 'mut-1',
              userId: const Value('user-1'),
              deviceId: 'dev',
              entityType: 'seal',
              operation: 'create',
              payload: '{"id":"seal-1"}',
              createdAt: DateTime.now(),
            ),
          );

      final existing = await (db.select(db.localSeals)
            ..where((s) => s.id.equals('seal-1')))
          .getSingle();
      final flags = await sealListCacheSyncFlags(
        db,
        sealId: 'seal-1',
        existing: existing,
        userId: 'user-1',
      );

      expect(flags.isSynced, isFalse);
    });
  });

  group('remapLocalSealIdAfterPush', () {
    test('moves seal row and re-links photos', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      await db.into(db.localSeals).insert(
            LocalSealsCompanion.insert(
              id: 'local-id',
              jobId: 'job-1',
              floorId: 'floor-1',
              sealNumber: '7',
              system: 'S',
              construction: 'C',
              location: 'L',
              fireRating: 'EI',
              updatedAt: DateTime.now(),
            ),
          );
      await db.into(db.localPhotos).insert(
            LocalPhotosCompanion.insert(
              id: 'photo-1',
              sealId: 'local-id',
              localPath: '/data/a.webp',
              createdAt: DateTime.now(),
            ),
          );

      await remapLocalSealIdAfterPush(db, 'local-id', 'server-id');

      expect(
        await (db.select(db.localSeals)
              ..where((s) => s.id.equals('local-id')))
            .getSingleOrNull(),
        isNull,
      );
      final seal = await (db.select(db.localSeals)
            ..where((s) => s.id.equals('server-id')))
          .getSingle();
      expect(seal.sealNumber, '7');
      expect(seal.isSynced, isTrue);

      final photo = await (db.select(db.localPhotos)
            ..where((p) => p.id.equals('photo-1')))
          .getSingle();
      expect(photo.sealId, 'server-id');
    });
  });

  test('countQueuedOutboxItems counts conflict rows for user', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-conflict',
            mutationId: 'mut-c',
            userId: const Value('user-1'),
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            status: const Value('conflict'),
            createdAt: DateTime.now(),
          ),
        );

    expect(await countQueuedOutboxItems(db, userId: 'user-1'), 1);
    expect(await countQueuedOutboxItems(db, userId: 'user-2'), 0);
  });
}
