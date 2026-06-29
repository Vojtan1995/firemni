import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_plan_viewer.dart';

void main() {
  group('floor plan PDF render sizing', () {
    test('uses stable zoom buckets', () {
      expect(floorPlanPdfRenderBucket(0.75), 1);
      expect(floorPlanPdfRenderBucket(1.2), 1.5);
      expect(floorPlanPdfRenderBucket(2.4), 3);
      expect(floorPlanPdfRenderBucket(7.2), 4);
      expect(floorPlanPdfRenderBucket(24), 4);
    });

    test('caps longest rendered side', () {
      final size = floorPlanPdfRenderSize(
        width: 1200,
        height: 800,
        devicePixelRatio: 2,
        viewerScale: 8,
        maxRenderDim: 8000,
      );

      expect(size.width, closeTo(8000, 0.001));
      expect(size.height, closeTo(5333.333, 0.01));
    });
  });
}
