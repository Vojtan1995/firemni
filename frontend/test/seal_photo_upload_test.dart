import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/seals/seal_detail_screen.dart';
import 'package:ucpavky/features/seals/seal_photo_upload.dart';

void main() {
  group('photoUploadMediaType', () {
    test('maps webp/jpeg/png extensions', () {
      expect(photoUploadMediaType('/a.webp').mimeType, 'image/webp');
      expect(photoUploadMediaType('/a.jpg').mimeType, 'image/jpeg');
      expect(photoUploadMediaType('/a.jpeg').mimeType, 'image/jpeg');
      expect(photoUploadMediaType('/a.png').mimeType, 'image/png');
    });
  });

  group('isRecognizedImageHeader', () {
    test('recognizes jpeg and png magic bytes', () {
      expect(isRecognizedImageHeader([0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
      expect(
        isRecognizedImageHeader([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        isTrue,
      );
      expect(isRecognizedImageHeader([0x00, 0x01, 0x02]), isFalse);
    });
  });

  group('validateLocalPhotoFile', () {
    test('rejects missing file', () async {
      expect(
        () => validateLocalPhotoFile('/nonexistent/photo.webp'),
        throwsStateError,
      );
    });

    test('accepts small png file', () async {
      final dir = Directory.systemTemp.createTempSync('photo_upload_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final file = File('${dir.path}/tiny.png');
      await file.writeAsBytes([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
      ]);

      await validateLocalPhotoFile(file.path);
      final prepared = await preparePhotoForUpload(file.path);
      expect(prepared.isTemporary, isFalse);
      expect(prepared.contentType.mimeType, 'image/png');
      await prepared.dispose();
    });
  });

  group('photoSyncErrorMessage', () {
    test('extracts server error from DioException body', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/seals/x/photos'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 400,
          data: {'error': 'Nepodporovaný formát souboru (application/octet-stream)'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(
        photoSyncErrorMessage(err),
        'Nepodporovaný formát souboru (application/octet-stream)',
      );
    });

    test('falls back to generic message for unknown errors', () {
      expect(photoSyncErrorMessage(Exception('x')), 'Upload fotky selhal');
    });
  });

  group('resolvePhotoUploadSealId', () {
    test('returns null when seal is not synced', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      await db.into(db.localSeals).insert(
            LocalSealsCompanion.insert(
              id: 'local-seal',
              jobId: 'job-1',
              floorId: 'floor-1',
              sealNumber: '22',
              system: 'S',
              construction: 'C',
              location: 'L',
              fireRating: 'EI',
              updatedAt: DateTime.now(),
              isSynced: const Value(false),
            ),
          );
      await db.into(db.localPhotos).insert(
            LocalPhotosCompanion.insert(
              id: 'photo-1',
              sealId: 'local-seal',
              localPath: '/data/a.webp',
              createdAt: DateTime.now(),
            ),
          );

      final photo = await (db.select(db.localPhotos)
            ..where((p) => p.id.equals('photo-1')))
          .getSingle();

      expect(await resolvePhotoUploadSealId(db, photo), isNull);
    });

    test('returns server seal id when seal is synced', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      await db.into(db.localSeals).insert(
            LocalSealsCompanion.insert(
              id: 'server-seal-id',
              jobId: 'job-1',
              floorId: 'floor-1',
              sealNumber: '22',
              system: 'S',
              construction: 'C',
              location: 'L',
              fireRating: 'EI',
              updatedAt: DateTime.now(),
              isSynced: const Value(true),
            ),
          );
      await db.into(db.localPhotos).insert(
            LocalPhotosCompanion.insert(
              id: 'photo-1',
              sealId: 'server-seal-id',
              localPath: '/data/a.webp',
              createdAt: DateTime.now(),
            ),
          );

      final photo = await (db.select(db.localPhotos)
            ..where((p) => p.id.equals('photo-1')))
          .getSingle();

      expect(await resolvePhotoUploadSealId(db, photo), 'server-seal-id');
    });
  });

  test('mergePhotosForDisplay prefers done for api photo with stale failed local',
      () {
    final merged = mergePhotosForDisplay(
      [
        {'id': 'server-1', 'filePath': 'a.webp'},
      ],
      [
        LocalPhoto(
          id: 'server-1',
          sealId: 'seal-1',
          localPath: '/data/failed.webp',
          serverPath: null,
          status: 'failed',
          createdAt: DateTime.now(),
          nextRetryAt: null,
          retryCount: 1,
          lastError: 'Soubor není platný obrázek',
        ),
      ],
    );

    expect(merged.length, 1);
    expect(merged.first['status'], 'done');
    expect(merged.first['lastError'], isNull);
  });
}
