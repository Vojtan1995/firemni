import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';

/// FE-02: ověření čtení seznamu pater z Drift a zachování outboxu.
void main() {
  test('loads floors for job from Drift ordered by sortOrder', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localFloors).insert(
          LocalFloorsCompanion.insert(
            id: 'floor-2',
            jobId: 'job-1',
            name: '2. NP',
            sortOrder: const Value(2),
            updatedAt: DateTime.now(),
          ),
        );
    await db.into(db.localFloors).insert(
          LocalFloorsCompanion.insert(
            id: 'floor-1',
            jobId: 'job-1',
            name: '1. NP',
            sortOrder: const Value(1),
            updatedAt: DateTime.now(),
          ),
        );

    final rows = await (db.select(db.localFloors)
          ..where((f) => f.jobId.equals('job-1') & f.deletedAt.isNull())
          ..orderBy([
            (f) => OrderingTerm.asc(f.sortOrder),
            (f) => OrderingTerm.asc(f.name)
          ]))
        .get();

    expect(rows.length, 2);
    expect(rows.first.name, '1. NP');
    expect(rows.last.name, '2. NP');
  });

  test('deleted floor tombstone is excluded from offline list query', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localFloors).insert(
          LocalFloorsCompanion.insert(
            id: 'floor-active',
            jobId: 'job-1',
            name: '1. NP',
            sortOrder: const Value(1),
            updatedAt: DateTime.now(),
          ),
        );
    await db.into(db.localFloors).insert(
          LocalFloorsCompanion.insert(
            id: 'floor-deleted',
            jobId: 'job-1',
            name: '2. NP',
            sortOrder: const Value(2),
            deletedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );

    final rows = await (db.select(db.localFloors)
          ..where((f) => f.jobId.equals('job-1') & f.deletedAt.isNull()))
        .get();

    expect(rows.length, 1);
    expect(rows.single.id, 'floor-active');
  });

  test('pending outbox rows are not removed when caching floors', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-fe02',
            mutationId: 'mut-fe02',
            deviceId: 'dev-1',
            entityType: 'seal',
            operation: 'create',
            payload: '{"floorId":"floor-1"}',
            createdAt: DateTime.now(),
          ),
        );

    await db.into(db.localFloors).insertOnConflictUpdate(
          LocalFloorsCompanion.insert(
            id: 'floor-1',
            jobId: 'job-1',
            name: '1. NP',
            sortOrder: const Value(1),
            updatedAt: DateTime.now(),
          ),
        );

    final outbox = await db.select(db.localOutbox).get();
    expect(outbox.length, 1);
    expect(outbox.first.status, 'pending');

    final floors = await (db.select(db.localFloors)
          ..where((f) => f.jobId.equals('job-1')))
        .get();
    expect(floors.length, 1);
  });
}
