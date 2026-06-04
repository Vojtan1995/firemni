import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../database/database.dart';

void logPhotoUpload(String message) {
  debugPrint('[PhotoUpload] $message');
}

/// MIME type for multipart photo upload — backend multer rejects octet-stream.
MediaType photoUploadMediaType(String filePath) {
  switch (p.extension(filePath).toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return MediaType('image', 'jpeg');
    case '.png':
      return MediaType('image', 'png');
    case '.webp':
      return MediaType('image', 'webp');
    default:
      return MediaType('image', 'jpeg');
  }
}

/// Validates local photo file before upload.
Future<void> validateLocalPhotoFile(String localPath) async {
  final file = File(localPath);
  if (!await file.exists()) {
    throw StateError('Lokální soubor fotky nenalezen: $localPath');
  }
  final length = await file.length();
  if (length == 0) {
    throw StateError('Lokální soubor fotky je prázdný');
  }
  final header = await file.openRead(0, 12).first;
  if (!isRecognizedImageHeader(header)) {
    throw StateError('Lokální soubor není rozpoznatelný obrázek');
  }
}

bool isRecognizedImageHeader(List<int> header) {
  if (header.length >= 3 &&
      header[0] == 0xFF &&
      header[1] == 0xD8 &&
      header[2] == 0xFF) {
    return true;
  }
  if (header.length >= 8 &&
      header[0] == 0x89 &&
      header[1] == 0x50 &&
      header[2] == 0x4E &&
      header[3] == 0x47) {
    return true;
  }
  if (header.length >= 12 &&
      header[0] == 0x52 &&
      header[1] == 0x49 &&
      header[2] == 0x46 &&
      header[3] == 0x46 &&
      header[8] == 0x57 &&
      header[9] == 0x45 &&
      header[10] == 0x42 &&
      header[11] == 0x50) {
    return true;
  }
  return false;
}

Future<String> _transcodeToJpeg(String sourcePath) async {
  final tempDir = await getTemporaryDirectory();
  final dest = p.join(tempDir.path, '${const Uuid().v4()}.jpg');
  final result = await FlutterImageCompress.compressAndGetFile(
    sourcePath,
    dest,
    quality: 90,
    format: CompressFormat.jpeg,
  );
  if (result == null) {
    throw StateError('Převod fotky na JPEG se nezdařil');
  }
  final out = File(result.path);
  if (!await out.exists() || await out.length() == 0) {
    throw StateError('Převod fotky na JPEG vytvořil prázdný soubor');
  }
  return result.path;
}

/// File path and metadata ready for multipart upload.
class PreparedPhotoUpload {
  PreparedPhotoUpload({
    required this.path,
    required this.filename,
    required this.contentType,
    this.isTemporary = false,
  });

  final String path;
  final String filename;
  final MediaType contentType;
  final bool isTemporary;

  Future<void> dispose() async {
    if (!isTemporary) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Prepares a local seal photo for server upload (WebP → JPEG fallback when needed).
Future<PreparedPhotoUpload> preparePhotoForUpload(String localPath) async {
  logPhotoUpload('prepare started: $localPath');
  await validateLocalPhotoFile(localPath);

  final file = File(localPath);
  final length = await file.length();
  logPhotoUpload('bytes length: $length');

  final ext = p.extension(localPath).toLowerCase();
  final useJpegFallback = ext == '.webp';

  if (useJpegFallback) {
    logPhotoUpload('using jpeg fallback');
    final jpegPath = await _transcodeToJpeg(localPath);
    final jpegLength = await File(jpegPath).length();
    logPhotoUpload('jpeg bytes length: $jpegLength');
    logPhotoUpload('multipart ready: $jpegPath');
    return PreparedPhotoUpload(
      path: jpegPath,
      filename: 'photo.jpg',
      contentType: MediaType('image', 'jpeg'),
      isTemporary: true,
    );
  }

  final filename = p.basename(localPath).isNotEmpty
      ? p.basename(localPath)
      : 'photo.jpg';
  logPhotoUpload('multipart ready: $localPath');
  return PreparedPhotoUpload(
    path: localPath,
    filename: filename,
    contentType: photoUploadMediaType(localPath),
  );
}

Future<MultipartFile> multipartFromPrepared(PreparedPhotoUpload prepared) {
  return MultipartFile.fromFile(
    prepared.path,
    filename: prepared.filename,
    contentType: prepared.contentType,
  );
}

/// Builds multipart file after [preparePhotoForUpload]. Caller must [PreparedPhotoUpload.dispose].
Future<({MultipartFile multipart, PreparedPhotoUpload prepared})>
    sealPhotoMultipartFile(String filePath) async {
  final prepared = await preparePhotoForUpload(filePath);
  final multipart = await multipartFromPrepared(prepared);
  return (multipart: multipart, prepared: prepared);
}

/// Human-readable upload error for SyncScreen / retry state.
String photoSyncErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'] as String;
    }
    final status = error.response?.statusCode;
    if (status == 400) {
      return 'Server odmítl fotku — zkontrolujte formát souboru';
    }
    if (status == 404) {
      return 'Ucpávka na serveru nenalezena — nejdřív synchronizujte ucpávku';
    }
    if (status == 403) {
      return 'Nemáte oprávnění nahrát fotku k této ucpávce';
    }
    if (status == 413) {
      return 'Fotka je příliš velká';
    }
  }
  return 'Upload fotky selhal';
}

/// Seal id for POST /api/seals/:id/photos — must be synced server entity id.
Future<String?> resolvePhotoUploadSealId(AppDatabase db, LocalPhoto photo) async {
  final seal = await (db.select(db.localSeals)
        ..where((s) => s.id.equals(photo.sealId)))
      .getSingleOrNull();
  if (seal == null) {
    return photo.sealId;
  }
  if (!seal.isSynced || seal.syncConflict) {
    return null;
  }
  return seal.id;
}

/// Reset failed photo for manual retry from detail screen.
Future<void> resetPhotoForRetry(AppDatabase db, String photoId) async {
  await (db.update(db.localPhotos)..where((p) => p.id.equals(photoId))).write(
    const LocalPhotosCompanion(
      status: Value('pending'),
      lastError: Value(null),
      nextRetryAt: Value(null),
      retryCount: Value(0),
    ),
  );
}
