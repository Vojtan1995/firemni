import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../../database/database.dart';

/// MIME type for multipart photo upload — backend multer rejects octet-stream.
MediaType photoUploadMediaType(String filePath) {
  switch (p.extension(filePath).toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return MediaType('image', 'jpeg');
    case '.png':
      return MediaType('image', 'png');
    case '.webp':
    default:
      return MediaType('image', 'webp');
  }
}

Future<MultipartFile> sealPhotoMultipartFile(String filePath) async {
  final base = p.basename(filePath);
  final filename = base.isNotEmpty ? base : 'photo.webp';
  return MultipartFile.fromFile(
    filePath,
    filename: filename,
    contentType: photoUploadMediaType(filePath),
  );
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
