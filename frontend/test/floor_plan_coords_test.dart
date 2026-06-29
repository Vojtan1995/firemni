import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_drawing_upload.dart';

void main() {
  const canvas = Size(800, 600);

  test('tapToNormalizedMarker converts tap to 0..1', () {
    final normalized = tapToNormalizedMarker(const Offset(400, 300), canvas);
    expect(normalized.dx, closeTo(0.5, 0.001));
    expect(normalized.dy, closeTo(0.5, 0.001));
  });

  test('tapToNormalizedMarker clamps to bounds', () {
    final normalized = tapToNormalizedMarker(const Offset(900, -10), canvas);
    expect(normalized.dx, 1.0);
    expect(normalized.dy, 0.0);
  });

  test('normalizedMarkerToPixel round-trips center', () {
    const normalized = Offset(0.25, 0.75);
    final pixel = normalizedMarkerToPixel(normalized, canvas);
    expect(pixel.dx, 200.0);
    expect(pixel.dy, 450.0);
  });

  test('focusTransformForMarker centers marker', () {
    final matrix = focusTransformForMarker(
      x: 0.5,
      y: 0.5,
      canvasSize: canvas,
      scale: 2.0,
    );
    expect(matrix.getMaxScaleOnAxis(), closeTo(2.0, 0.001));
  });

  group('labelCenterPixel', () {
    test('without offset matches the marker position (legacy behavior)', () {
      final pixel = labelCenterPixel(x: 0.5, y: 0.5, canvasSize: canvas);
      expect(pixel.dx, closeTo(400, 0.001));
      expect(pixel.dy, closeTo(300, 0.001));
    });

    test('null offset behaves the same as zero offset', () {
      final withNull = labelCenterPixel(
        x: 0.5,
        y: 0.5,
        offsetX: null,
        offsetY: null,
        canvasSize: canvas,
      );
      final withZero = labelCenterPixel(
        x: 0.5,
        y: 0.5,
        offsetX: 0,
        offsetY: 0,
        canvasSize: canvas,
      );
      expect(withNull, withZero);
    });

    test('applies a positive offset away from the marker', () {
      final pixel = labelCenterPixel(
        x: 0.5,
        y: 0.5,
        offsetX: 0.1,
        offsetY: -0.05,
        canvasSize: canvas,
      );
      expect(pixel.dx, closeTo(480, 0.001));
      expect(pixel.dy, closeTo(270, 0.001));
    });
  });

  group('dragDeltaToNormalizedOffset', () {
    test('converts pixel delta into normalized units', () {
      final delta = dragDeltaToNormalizedOffset(const Offset(80, 60), canvas);
      expect(delta.dx, closeTo(0.1, 0.001));
      expect(delta.dy, closeTo(0.1, 0.001));
    });

    test('returns zero for a degenerate canvas size', () {
      final delta =
          dragDeltaToNormalizedOffset(const Offset(80, 60), Size.zero);
      expect(delta, Offset.zero);
    });
  });
}
