import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_drawing_status.dart';

void main() {
  test('FloorDrawingDownloadStatus labels', () {
    expect(FloorDrawingDownloadStatus.downloaded.label, 'Staženo');
    expect(FloorDrawingDownloadStatus.downloading.label, 'Stahuje se');
    expect(FloorDrawingDownloadStatus.missing.label, 'Chybí');
    expect(FloorDrawingDownloadStatus.error.label, 'Chyba stažení');
  });

  test('fromDb roundtrip', () {
    expect(
      FloorDrawingDownloadStatusX.fromDb('downloaded'),
      FloorDrawingDownloadStatus.downloaded,
    );
    expect(
      FloorDrawingDownloadStatus.downloaded.toDb(),
      'downloaded',
    );
  });
}
