import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';

/// FE-01: ověření čtení seznamu ucpávek z Drift a zachování outboxu.
void main() {
  test('loads seals for floor from Drift ordered by seal number', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-b',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '2',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            updatedAt: DateTime.now(),
          ),
        );
    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-a',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '1',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            updatedAt: DateTime.now(),
          ),
        );

    final rows = await (db.select(db.localSeals)
          ..where((s) => s.floorId.equals('floor-1') & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.sealNumber)]))
        .get();

    expect(rows.length, 2);
    expect(rows.first.sealNumber, '1');
    expect(rows.last.sealNumber, '2');
  });

  test('deleted seal tombstone is excluded from offline list query', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-active',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '1',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            updatedAt: DateTime.now(),
          ),
        );
    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-deleted',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '2',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            deletedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );

    final rows = await (db.select(db.localSeals)
          ..where((s) => s.floorId.equals('floor-1') & s.deletedAt.isNull()))
        .get();

    expect(rows.length, 1);
    expect(rows.single.id, 'seal-active');
  });

  test('pending outbox rows are not removed when caching seals', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-1',
            mutationId: 'mut-fe01',
            deviceId: 'dev-1',
            entityType: 'seal',
            operation: 'create',
            payload: '{"sealNumber":"99"}',
            createdAt: DateTime.now(),
          ),
        );

    await db.into(db.localSeals).insertOnConflictUpdate(
          LocalSealsCompanion.insert(
            id: 'local-seal-1',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '99',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            isSynced: const Value(false),
            updatedAt: DateTime.now(),
          ),
        );

    final outbox = await db.select(db.localOutbox).get();
    expect(outbox.length, 1);
    expect(outbox.first.status, 'pending');

    final seals = await (db.select(db.localSeals)
          ..where((s) => s.floorId.equals('floor-1')))
        .get();
    expect(seals.length, 1);
    expect(seals.first.isSynced, false);
  });
}
