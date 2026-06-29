import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/seals/seal_detail_screen.dart';

/// Offline detail ucpávky: jsonPayload, prostupy, fotky, zachování outboxu.
void main() {
  test('sealDetailFromLocal restores entries and materials from jsonPayload',
      () async {
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

    final row = await (db.select(db.localSeals)
          ..where((s) => s.id.equals('seal-1')))
        .getSingle();
    final seal = sealDetailFromLocal(row, []);

    expect(seal, isNotNull);
    expect(seal!['sealNumber'], '42');
    final entries = seal['entries'] as List;
    expect(entries.length, 1);
    expect((entries.first as Map)['entryType'], 'Kabel');
    final mats = (entries.first as Map)['materials'] as List;
    expect(mats.length, 2);
  });

  test('sealDetailFromLocal uses note columns over jsonPayload', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-notes',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '7',
            system: 'S1',
            construction: 'Stěna',
            location: 'Chodba',
            fireRating: 'EI 60',
            note: const Value('public from column'),
            internalNote: const Value('internal from column'),
            jsonPayload: const Value(
              '{"entries":[],"photos":[],"note":"stale","internalNote":"stale"}',
            ),
            updatedAt: DateTime.now(),
          ),
        );

    final row = await (db.select(db.localSeals)
          ..where((s) => s.id.equals('seal-notes')))
        .getSingle();
    final seal = sealDetailFromLocal(row, [])!;

    expect(seal['note'], 'public from column');
    expect(seal['internalNote'], 'internal from column');
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

    await cacheSealDetailFromApi(
        db,
        {
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
        },
        userId: 'user-1');

    final outbox = await db.select(db.localOutbox).get();
    expect(outbox.length, 1);
    expect(outbox.first.status, 'pending');

    final row = await (db.select(db.localSeals)
          ..where((s) => s.id.equals('seal-1')))
        .getSingle();
    expect(row.jsonPayload, isNotNull);
    expect(jsonDecode(row.jsonPayload!)['entries'], isA<List>());
  });

  test('cacheSealDetailFromApi stores photo metadata for current user',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 6, 29);

    await cacheSealDetailFromApi(
        db,
        {
          'id': 'seal-photo-cache',
          'jobId': 'job-1',
          'floorId': 'floor-1',
          'sealNumber': '100',
          'system': 'S',
          'construction': 'C',
          'location': 'L',
          'fireRating': 'EI',
          'status': 'draft',
          'version': 1,
          'updatedAt': now.toIso8601String(),
          'entries': [],
          'photos': [
            {
              'id': 'photo-1',
              'filePath': 'server/photo.webp',
              'createdAt': now.toIso8601String(),
            },
          ],
        },
        userId: 'user-1');

    final photo = await (db.select(db.localPhotos)
          ..where((p) => p.id.equals('photo-1')))
        .getSingle();
    expect(photo.userId, 'user-1');
    expect(photo.status, 'done');
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

    final row = await (db.select(db.localSeals)
          ..where((s) => s.id.equals('seal-1')))
        .getSingle();
    final photos = await (db.select(db.localPhotos)
          ..where((p) => p.sealId.equals('seal-1')))
        .get();
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

    final row = await (db.select(db.localSeals)
          ..where((s) => s.id.equals('seal-1')))
        .getSingle();
    final photos = await (db.select(db.localPhotos)
          ..where((p) => p.sealId.equals('seal-1')))
        .get();
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
