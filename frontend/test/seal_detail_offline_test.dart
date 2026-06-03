import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/seals/seal_detail_screen.dart';

/// Offline detail ucpávky: jsonPayload, prostupy, fotky, zachování outboxu.
void main() {
  test('sealDetailFromLocal restores entries and materials from jsonPayload', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    final detail = {
      'id': 'seal-1',
      'jobId': 'job-1',
      'floorId': 'floor-1',
      'sealNumber': '42',
      'system': 'S1',
      'construction': 'Stěna',
      'location': 'Chodba',
      'fireRating': 'EI 60',
      'status': 'draft',
      'version': 1,
      'entries': [
        {
          'entryType': 'Kabel',
          'dimension': '50',
          'quantity': 2,
          'insulation': 'Minerál',
          'materials': [
            {'material': 'Pěna'},
            {'material': 'Malta'},
          ],
        },
      ],
      'photos': [
        {'id': 'ph-1', 'filePath': 'seals/photo1.webp'},
      ],
    };

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-1',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '42',
            system: 'S1',
            construction: 'Stěna',
            location: 'Chodba',
            fireRating: 'EI 60',
            jsonPayload: Value(jsonEncode(detail)),
            updatedAt: DateTime.now(),
          ),
        );

    final row = await (db.select(db.localSeals)..where((s) => s.id.equals('seal-1'))).getSingle();
    final seal = sealDetailFromLocal(row, []);

    expect(seal, isNotNull);
    expect(seal!['sealNumber'], '42');
    final entries = seal['entries'] as List;
    expect(entries.length, 1);
    expect((entries.first as Map)['entryType'], 'Kabel');
    final mats = (entries.first as Map)['materials'] as List;
    expect(mats.length, 2);
  });

  test('cacheSealDetailFromApi preserves pending outbox rows', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-detail',
            mutationId: 'mut-detail',
            deviceId: 'dev-1',
            entityType: 'seal',
            operation: 'create',
            payload: '{"sealNumber":"99"}',
            createdAt: DateTime.now(),
          ),
        );

    await cacheSealDetailFromApi(db, {
      'id': 'seal-1',
      'jobId': 'job-1',
      'floorId': 'floor-1',
      'sealNumber': '99',
      'system': 'S',
      'construction': 'C',
      'location': 'L',
      'fireRating': 'EI',
      'status': 'draft',
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'entries': [
        {
          'entryType': 'Kabel',
          'dimension': '10',
          'quantity': 1,
          'insulation': 'X',
          'materials': [
            {'material': 'Pěna'},
          ],
        },
      ],
      'photos': [],
    });

    final outbox = await db.select(db.localOutbox).get();
    expect(outbox.length, 1);
    expect(outbox.first.status, 'pending');

    final row = await (db.select(db.localSeals)..where((s) => s.id.equals('seal-1'))).getSingle();
    expect(row.jsonPayload, isNotNull);
    expect(jsonDecode(row.jsonPayload!)['entries'], isA<List>());
  });

  test('sealDetailFromLocal includes pending local photo metadata', () async {
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
            jsonPayload: const Value('{"entries":[],"photos":[]}'),
            updatedAt: DateTime.now(),
          ),
        );

    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'local-ph',
            sealId: 'seal-1',
            localPath: '/tmp/pending.webp',
            status: const Value('pending'),
            createdAt: DateTime.now(),
          ),
        );

    final row = await (db.select(db.localSeals)..where((s) => s.id.equals('seal-1'))).getSingle();
    final photos = await (db.select(db.localPhotos)..where((p) => p.sealId.equals('seal-1'))).get();
    final seal = sealDetailFromLocal(row, photos)!;

    final photoList = seal['photos'] as List;
    expect(photoList.length, 1);
    expect((photoList.first as Map)['localPath'], '/tmp/pending.webp');
    expect((photoList.first as Map)['status'], 'pending');
  });

  test('sealDetailFromLocal includes failed photo metadata', () async {
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
            jsonPayload: const Value('{"entries":[],"photos":[]}'),
            updatedAt: DateTime.now(),
          ),
        );

    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'failed-ph',
            sealId: 'seal-1',
            localPath: '/tmp/missing.webp',
            status: const Value('failed'),
            lastError: const Value('network error'),
            createdAt: DateTime.now(),
          ),
        );

    final row = await (db.select(db.localSeals)..where((s) => s.id.equals('seal-1'))).getSingle();
    final photos = await (db.select(db.localPhotos)..where((p) => p.sealId.equals('seal-1'))).get();
    final seal = sealDetailFromLocal(row, photos)!;

    final photoList = seal['photos'] as List;
    expect(photoList.length, 1);
    expect((photoList.first as Map)['status'], 'failed');
    expect((photoList.first as Map)['lastError'], 'network error');
  });

  test('mergePhotosForDisplay adds pending local-only photos', () {
    final merged = mergePhotosForDisplay(
      [
        {'id': 'server-1', 'filePath': 'a.webp'},
      ],
      [
        LocalPhoto(
          id: 'local-pending',
          sealId: 'seal-1',
          localPath: '/data/pending.webp',
          serverPath: null,
          status: 'pending',
          createdAt: DateTime.now(),
          nextRetryAt: null,
          retryCount: 0,
          lastError: null,
        ),
      ],
    );

    expect(merged.length, 2);
    expect(merged.first['status'], 'done');
    expect(merged.last['id'], 'local-pending');
    expect(merged.last['status'], 'pending');
  });
}
