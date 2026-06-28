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

  test('remap after push moves photos to the server seal id and marks synced',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    const localId = 'local-seal';
    const serverId = 'server-seal';

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: localId,
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '7',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            isSynced: const Value(false),
            updatedAt: DateTime.now(),
          ),
        );
    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'photo-1',
            sealId: localId,
            localPath: '/tmp/p1.webp',
            createdAt: DateTime.now(),
          ),
        );

    await remapLocalSealIdAfterPush(db, localId, serverId);

    // Lokální ucpávka má nově server-id a je označená jako synced.
    final remapped = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(serverId)))
        .getSingleOrNull();
    expect(remapped, isNotNull);
    expect(remapped!.isSynced, isTrue);
    final old = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(localId)))
        .getSingleOrNull();
    expect(old == null, isTrue);

    // Fotka následuje ucpávku na nové server-id (žádná osamělá fotka).
    final photo = await (db.select(db.localPhotos)
          ..where((p) => p.id.equals('photo-1')))
        .getSingle();
    expect(photo.sealId, serverId);
  });
}
