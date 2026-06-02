import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/seals/seal_duplicate_local.dart';
import 'package:ucpavky/features/sync/sync_conflict.dart';

void main() {
  test('isDuplicateConflictMessage detects duplicate text', () {
    expect(
      isDuplicateConflictMessage('Duplicitní číslo ucpávky na tomto patře'),
      isTrue,
    );
    expect(isDuplicateConflictMessage('Verze entity se neshoduje'), isFalse);
  });

  test('findLocalDuplicateSeal finds same floor number (T12)', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-existing',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '42',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            updatedAt: DateTime.now(),
          ),
        );

    final dup = await findLocalDuplicateSeal(
      db,
      jobId: 'job-1',
      floorId: 'floor-1',
      sealNumber: '42',
    );
    expect(dup?.id, 'seal-existing');

    final otherFloor = await findLocalDuplicateSeal(
      db,
      jobId: 'job-1',
      floorId: 'floor-2',
      sealNumber: '42',
    );
    expect(otherFloor, isNull);
  });

  test('fixDuplicateSealNumberAndRequeue updates seal and outbox (T12)',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-1',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '99',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            syncConflict: const Value(true),
            updatedAt: DateTime.now(),
          ),
        );
    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-1',
            mutationId: 'mut-old',
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload:
                '{"id":"seal-1","jobId":"job-1","floorId":"floor-1","sealNumber":"99"}',
            status: const Value('conflict'),
            conflictMessage: const Value('Duplicitní číslo ucpávky na tomto patře'),
            createdAt: DateTime.now(),
          ),
        );

    final err = await fixDuplicateSealNumberAndRequeue(
      db,
      outboxId: 'out-1',
      newSealNumber: '100',
    );
    expect(err, isNull);

    final seal = await (db.select(db.localSeals)
          ..where((s) => s.id.equals('seal-1')))
        .getSingle();
    expect(seal.sealNumber, '100');
    expect(seal.syncConflict, isFalse);

    final outbox = await (db.select(db.localOutbox)
          ..where((o) => o.id.equals('out-1')))
        .getSingle();
    expect(outbox.status, 'pending');
    expect(outbox.mutationId, isNot('mut-old'));
    final payload = outbox.payload;
    expect(payload, contains('"sealNumber":"100"'));
  });
}
