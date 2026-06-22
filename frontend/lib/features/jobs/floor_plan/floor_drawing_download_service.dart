import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../../database/database.dart';
import '../floor_drawing_storage.dart';
import 'floor_drawing_status.dart';
import '../../sync/sync_retry.dart';

typedef DrawingDownloadedCallback = void Function(String floorId);

DrawingDownloadedCallback? onFloorDrawingDownloaded;

/// Stáhne soubor výkresu a uloží do lokální cache.
Future<bool> downloadFloorDrawingFile({
  required Dio dio,
  required AppDatabase db,
  required String jobId,
  required String floorId,
  required Map<String, dynamic> meta,
}) async {
  await (db.update(db.localFloorDrawings)
        ..where((d) => d.floorId.equals(floorId)))
      .write(LocalFloorDrawingsCompanion(
    downloadStatus: Value(FloorDrawingDownloadStatus.downloading.toDb()),
    lastError: const Value(null),
  ));

  try {
    final res = await dio.get(
      '/api/jobs/$jobId/floors/$floorId/drawing/file',
      options: Options(responseType: ResponseType.bytes),
    );
    Uint8List? bytes;
    final data = res.data;
    if (data is Uint8List) {
      bytes = data;
    } else if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    }
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Prázdná odpověď výkresu');
    }

    final mime = meta['mimeType'] as String? ?? 'image/webp';
    final ext = floorDrawingExtensionForMime(mime);
    final localPath = await persistFloorDrawingBytes(
      floorId,
      bytes,
      extension: ext,
    );

    await db.into(db.localFloorDrawings).insertOnConflictUpdate(
          LocalFloorDrawingsCompanion.insert(
            floorId: floorId,
            jobId: jobId,
            filePath: meta['filePath'] as String? ?? '',
            localPath: Value(localPath),
            mimeType: mime,
            width: meta['width'] as int? ?? 1,
            height: meta['height'] as int? ?? 1,
            downloadStatus: Value(FloorDrawingDownloadStatus.downloaded.toDb()),
            retryCount: const Value(0),
            nextRetryAt: const Value(null),
            lastError: const Value(null),
            updatedAt: DateTime.tryParse(meta['updatedAt'] as String? ?? '') ??
                DateTime.now(),
          ),
        );

    onFloorDrawingDownloaded?.call(floorId);
    return true;
  } catch (e) {
    final row = await (db.select(db.localFloorDrawings)
          ..where((d) => d.floorId.equals(floorId)))
        .getSingleOrNull();
    final nextCount = (row?.retryCount ?? 0) + 1;
    final now = DateTime.now();
    await (db.update(db.localFloorDrawings)
          ..where((d) => d.floorId.equals(floorId)))
        .write(LocalFloorDrawingsCompanion(
      downloadStatus: Value(FloorDrawingDownloadStatus.error.toDb()),
      retryCount: Value(nextCount),
      lastError: Value(e.toString()),
      nextRetryAt: Value(syncNextRetryAt(nextCount, now)),
    ));
    return false;
  }
}

Future<bool> upsertFloorDrawingMetadata(
  AppDatabase db, {
  required String floorId,
  required String jobId,
  required Map<String, dynamic> meta,
  String? localPath,
}) async {
  final incomingFilePath = meta['filePath'] as String? ?? '';
  final existing = await (db.select(db.localFloorDrawings)
        ..where((d) => d.floorId.equals(floorId)))
      .getSingleOrNull();
  final drawingChanged = existing != null &&
      existing.filePath.isNotEmpty &&
      incomingFilePath.isNotEmpty &&
      existing.filePath != incomingFilePath;

  if (drawingChanged) {
    final oldPath = existing.localPath;
    if (oldPath != null && oldPath.isNotEmpty) {
      try {
        final oldFile = File(oldPath);
        if (oldFile.existsSync()) oldFile.deleteSync();
      } catch (_) {}
    }
    await (db.delete(db.localSealMarkers)
          ..where((m) => m.floorId.equals(floorId)))
        .go();
    await (db.update(db.localSeals)
          ..where((s) => s.floorId.equals(floorId) & s.deletedAt.isNull()))
        .write(
      const LocalSealsCompanion(markerPlacementPending: Value(true)),
    );
  }

  final hasFile =
      localPath != null && localPath.isNotEmpty && File(localPath).existsSync();
  await db.into(db.localFloorDrawings).insertOnConflictUpdate(
        LocalFloorDrawingsCompanion.insert(
          floorId: floorId,
          jobId: jobId,
          filePath: incomingFilePath,
          localPath: Value(localPath),
          mimeType: meta['mimeType'] as String? ?? 'image/webp',
          width: meta['width'] as int? ?? 1,
          height: meta['height'] as int? ?? 1,
          downloadStatus: Value(
            hasFile
                ? FloorDrawingDownloadStatus.downloaded.toDb()
                : FloorDrawingDownloadStatus.downloading.toDb(),
          ),
          updatedAt: DateTime.tryParse(meta['updatedAt'] as String? ?? '') ??
              DateTime.now(),
        ),
      );
  return drawingChanged;
}

/// Zpracuje výkresy čekající na stažení (retry fronta).
Future<int> processPendingDrawingDownloads({
  required Dio dio,
  required AppDatabase db,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final rows = await db.select(db.localFloorDrawings).get();
  var processed = 0;

  for (final row in rows) {
    if (row.downloadStatus == FloorDrawingDownloadStatus.downloaded.toDb()) {
      if (row.localPath != null && File(row.localPath!).existsSync()) {
        continue;
      }
    }
    if (row.downloadStatus == FloorDrawingDownloadStatus.missing.toDb()) {
      continue;
    }
    if (row.nextRetryAt != null && row.nextRetryAt!.isAfter(at)) {
      continue;
    }
    if (row.jobId.isEmpty) continue;

    final ok = await downloadFloorDrawingFile(
      dio: dio,
      db: db,
      jobId: row.jobId,
      floorId: row.floorId,
      meta: {
        'filePath': row.filePath,
        'mimeType': row.mimeType,
        'width': row.width,
        'height': row.height,
        'updatedAt': row.updatedAt.toIso8601String(),
      },
    );
    if (ok) processed++;
  }
  return processed;
}
