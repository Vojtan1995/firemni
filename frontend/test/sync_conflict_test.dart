import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/sync/sync_conflict.dart';

/// FE-03: zobrazení sync konfliktů a skrytí bez smazání dat.
void main() {
  test('loads active conflicts with metadata', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localJobs).insert(
          LocalJobsCompanion.insert(
            id: 'job-1',
            projectNumber: '12345678',
            name: 'Test stavba',
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
    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-1',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '42',
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
            id: 'out-conflict',
            mutationId: 'mut-1',
            userId: const Value('user-1'),
            deviceId: 'dev-1',
            entityType: 'seal',
            operation: 'create',
            payload: jsonEncode({
              'jobId': 'job-1',
              'floorId': 'floor-1',
              'sealNumber': '42',
            }),
            status: const Value('conflict'),
            conflictMessage: const Value('Duplicitní číslo ucpávky na tomto patře'),
            createdAt: DateTime(2026, 5, 27, 10, 30),
          ),
        );

    final conflicts = await loadActiveSyncConflicts(db, userId: 'user-1');
    expect(conflicts.length, 1);
    expect(conflicts.first.sealNumber, '42');
    expect(conflicts.first.jobLabel, contains('12345678'));
    expect(conflicts.first.floorName, '1. NP');
    expect(conflicts.first.conflictMessage, contains('Duplicitní'));
    expect(conflicts.first.operationLabel, 'Vytvoření');
  });

  test('dismiss hides conflict but keeps outbox and seal data', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-2',
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
            id: 'out-2',
            mutationId: 'mut-2',
            userId: const Value('user-1'),
            deviceId: 'dev-1',
            entityType: 'seal',
            operation: 'update',
            payload: jsonEncode({'id': 'seal-2', 'location': 'X'}),
            status: const Value('conflict'),
            conflictMessage: const Value('Ucpávka je zamčena'),
            createdAt: DateTime.now(),
          ),
        );

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-pending',
            mutationId: 'mut-3',
            userId: const Value('user-1'),
            deviceId: 'dev-1',
            entityType: 'seal',
            operation: 'create',
            payload: '{"sealNumber":"1"}',
            status: const Value('pending'),
            createdAt: DateTime.now(),
          ),
        );

    await dismissSyncConflict(db, 'out-2');

    final active = await loadActiveSyncConflicts(db, userId: 'user-1');
    expect(active, isEmpty);

    final outbox = await db.select(db.localOutbox).get();
    expect(outbox.length, 2);
    expect(outbox.any((o) => o.id == 'out-pending' && o.status == 'pending'), isTrue);

    final seal = await (db.select(db.localSeals)..where((s) => s.id.equals('seal-2'))).getSingle();
    expect(seal.sealNumber, '99');
    expect(seal.syncConflict, false);
  });
}
