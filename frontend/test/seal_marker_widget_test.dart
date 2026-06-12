import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan/seal_marker_widget.dart';

void main() {
  test('markerScaleForViewer at 1x zoom', () {
    expect(markerScaleForViewer(1.0), 1.0);
  });

  test('markerScaleForViewer at max 12x zoom', () {
    expect(markerScaleForViewer(12.0), closeTo(0.083, 0.001));
  });

  test('markerScaleForViewer clamps at min zoom out', () {
    expect(markerScaleForViewer(0.5), 2.0);
  });

  test('sealMarkerDimensions at max zoom scale ~0.08', () {
    final dims = sealMarkerDimensions(0.08);
    expect(dims.size, 6.0);
    expect(dims.borderWidth, 0.5);
    expect(dims.shadowBlur, 0.5);
  });

  test('sealMarkerDimensions at 1x scale', () {
    final dims = sealMarkerDimensions(1.0);
    expect(dims.size, 18.0);
    expect(dims.borderWidth, 1.5);
    expect(dims.fontSize, 7.0);
  });
}
