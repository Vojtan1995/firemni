import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_drawing_availability.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_drawing_status.dart';

void main() {
  group('FloorDrawingState', () {
    test('hasDrawingOnFloor when metadata present', () {
      const state = FloorDrawingState(
        status: FloorDrawingDownloadStatus.downloading,
        hasServerMetadata: true,
      );
      expect(state.hasDrawingOnFloor, isTrue);
      expect(state.isInteractive, isFalse);
    });

    test('hasDrawingOnFloor false when missing', () {
      const state = FloorDrawingState(
        status: FloorDrawingDownloadStatus.missing,
        hasServerMetadata: false,
      );
      expect(state.hasDrawingOnFloor, isFalse);
    });
  });

  group('resolveDownloadStatus', () {
    test('file on disk overrides downloading status', () {
      final row = LocalFloorDrawing(
        floorId: 'f1',
        jobId: 'j1',
        filePath: '/drawings/f1.webp',
        localPath: '/cache/f1.webp',
        mimeType: 'image/webp',
        width: 100,
        height: 100,
        downloadStatus: 'downloading',
        retryCount: 0,
        nextRetryAt: null,
        lastError: null,
        updatedAt: DateTime.now(),
      );
      expect(
        resolveDownloadStatus(row, fileExists: true),
        FloorDrawingDownloadStatus.downloaded,
      );
    });
  });

  group('computeMarkerPlacementPending', () {
    const drawingWithFloor = FloorDrawingState(
      status: FloorDrawingDownloadStatus.downloaded,
      hasServerMetadata: true,
    );
    const noDrawing = FloorDrawingState(
      status: FloorDrawingDownloadStatus.missing,
      hasServerMetadata: false,
    );

    test('pending when new seal on floor with drawing and no marker', () {
      expect(
        computeMarkerPlacementPending(
          isEdit: false,
          drawing: drawingWithFloor,
          markerPlacementConfirmed: false,
        ),
        isTrue,
      );
    });

    test('not pending when marker confirmed', () {
      expect(
        computeMarkerPlacementPending(
          isEdit: false,
          drawing: drawingWithFloor,
          markerPlacementConfirmed: true,
        ),
        isFalse,
      );
    });

    test('not pending when floor has no drawing', () {
      expect(
        computeMarkerPlacementPending(
          isEdit: false,
          drawing: noDrawing,
          markerPlacementConfirmed: false,
        ),
        isFalse,
      );
    });

    test('not pending on edit', () {
      expect(
        computeMarkerPlacementPending(
          isEdit: true,
          drawing: drawingWithFloor,
          markerPlacementConfirmed: false,
        ),
        isFalse,
      );
    });
  });
}
