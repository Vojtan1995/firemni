import 'dart:io';

import 'dart:typed_data';



import 'package:drift/drift.dart';



import '../../../database/database.dart';

import 'floor_drawing_status.dart';



class FloorDrawingState {

  const FloorDrawingState({

    required this.status,

    required this.hasServerMetadata,

    this.bytes,

    this.mimeType,

    this.width = 1,

    this.height = 1,

    this.lastError,

  });



  final FloorDrawingDownloadStatus status;

  final bool hasServerMetadata;

  final Uint8List? bytes;

  final String? mimeType;

  final int width;

  final int height;

  final String? lastError;



  bool get isInteractive =>

      status == FloorDrawingDownloadStatus.downloaded && bytes != null;



  /// Patro má výkres na serveru (metadata v cache), bez ohledu na stažení souboru.

  bool get hasDrawingOnFloor =>

      hasServerMetadata || status != FloorDrawingDownloadStatus.missing;
}

/// Určí, zda nová ucpávka má flag markerPlacementPending při uložení.
bool computeMarkerPlacementPending({
  required bool isEdit,
  required FloorDrawingState drawing,
  required bool markerPlacementConfirmed,
}) {
  return !isEdit && drawing.hasDrawingOnFloor && !markerPlacementConfirmed;
}

/// Odvodí stav stažení z DB řádku a případného souboru na disku.

FloorDrawingDownloadStatus resolveDownloadStatus(

  LocalFloorDrawing row, {

  bool? fileExists,

}) {

  final exists = fileExists ??

      (row.localPath != null && File(row.localPath!).existsSync());

  if (exists) return FloorDrawingDownloadStatus.downloaded;

  return FloorDrawingDownloadStatusX.fromDb(row.downloadStatus);

}



Future<FloorDrawingState> resolveFloorDrawingState(

  AppDatabase db, {

  required String floorId,

}) async {

  final row = await (db.select(db.localFloorDrawings)

        ..where((d) => d.floorId.equals(floorId)))

      .getSingleOrNull();



  if (row == null) {

    return const FloorDrawingState(

      status: FloorDrawingDownloadStatus.missing,

      hasServerMetadata: false,

    );

  }



  final fileExists =

      row.localPath != null && File(row.localPath!).existsSync();

  Uint8List? bytes;

  if (fileExists) {

    bytes = await File(row.localPath!).readAsBytes();

  }



  final dbStatus = FloorDrawingDownloadStatusX.fromDb(row.downloadStatus);

  final effectiveStatus = bytes != null && bytes.isNotEmpty

      ? FloorDrawingDownloadStatus.downloaded

      : dbStatus;



  if (fileExists &&

      bytes != null &&

      bytes.isNotEmpty &&

      dbStatus != FloorDrawingDownloadStatus.downloaded) {

    await (db.update(db.localFloorDrawings)

          ..where((d) => d.floorId.equals(floorId)))

        .write(

      LocalFloorDrawingsCompanion(

        downloadStatus: Value(FloorDrawingDownloadStatus.downloaded.toDb()),

        lastError: const Value(null),

        retryCount: const Value(0),

        nextRetryAt: const Value(null),

      ),

    );

  }



  return FloorDrawingState(

    status: effectiveStatus,

    hasServerMetadata: row.filePath.isNotEmpty,

    bytes: bytes?.isNotEmpty == true ? bytes : null,

    mimeType: row.mimeType,

    width: row.width,

    height: row.height,

    lastError: row.lastError,

  );

}



String drawingStatusLabelForFloor(

  AppDatabase db,

  String floorId, {

  FloorDrawingState? cached,

}) {

  return cached?.status.label ?? FloorDrawingDownloadStatus.missing.label;

}


