import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan/seal_marker_widget.dart';

void main() {
  test('markerScaleForViewer at 1x zoom', () {
    expect(markerScaleForViewer(1.0), closeTo(0.8889, 0.001));
  });

  test('markerScaleForViewer at 12x zoom', () {
    expect(markerScaleForViewer(12.0), closeTo(0.0310, 0.001));
  });

  test('markerScaleForViewer clamps onscreen size at min zoom out', () {
    expect(markerScaleForViewer(0.5), closeTo(1.7778, 0.001));
  });

  test('on-screen marker size shrinks as zoom increases', () {
    // velikost NA OBRAZOVCE = scale * kSealMarkerBaseSize * viewerScale
    double onScreenSize(double viewerScale) =>
        markerScaleForViewer(viewerScale) * kSealMarkerBaseSize * viewerScale;

    final atLowZoom = onScreenSize(1.0);
    final atMidZoom = onScreenSize(12.0);
    final atMaxZoom = onScreenSize(40.0);

    expect(atMidZoom, lessThan(atLowZoom));
    expect(atMaxZoom, lessThan(atMidZoom));
    // Při maximálním zoomu zůstává malá (ne nafouknutá) — dolní strop 6px.
    expect(atMaxZoom, closeTo(6.0, 0.001));
  });

  test('sealMarkerDimensions scales proportionally without a px floor', () {
    final dims = sealMarkerDimensions(0.08);
    expect(dims.size, closeTo(1.44, 0.001));
    expect(dims.borderWidth, closeTo(0.12, 0.001));
    expect(dims.shadowBlur, closeTo(0.16, 0.001));
  });

  test('sealMarkerDimensions at 1x scale', () {
    final dims = sealMarkerDimensions(1.0);
    expect(dims.size, 18.0);
    expect(dims.borderWidth, 1.5);
    expect(dims.fontSize, 7.0);
  });

  test('highlighted marker is proportionally larger at the same scale', () {
    final normal = sealMarkerDimensions(1.0);
    final highlighted = sealMarkerDimensions(1.0, highlighted: true);
    expect(highlighted.size, closeTo(normal.size * 1.3, 0.001));
  });

  test('sealMarkerTopLeft centers marker using current dimensions', () {
    final scale = markerScaleForViewer(12.0);
    final dims = sealMarkerDimensions(scale);
    final topLeft = sealMarkerTopLeft(
      x: 0.5,
      y: 0.5,
      canvasSize: const Size(800, 600),
      scale: scale,
    );

    expect(topLeft.dx, closeTo(400 - dims.size / 2, 0.001));
    expect(topLeft.dy, closeTo(300 - dims.size / 2, 0.001));
  });
}
