import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const lowResolutionWarningThresholdPx = 2500;

const lowResolutionWarningMessage =
    'Výkres má nízké rozlišení a při přiblížení může být rozmazaný.';

bool isPdfDrawingFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.pdf');
}

bool isRasterImageDrawingFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg');
}

bool shouldWarnLowResolution(int width, String fileName) {
  if (isPdfDrawingFileName(fileName)) return false;
  if (!isRasterImageDrawingFileName(fileName)) return false;
  return width < lowResolutionWarningThresholdPx;
}

Future<Size?> decodeRasterImageSize(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final size = Size(image.width.toDouble(), image.height.toDouble());
  image.dispose();
  return size;
}

/// Relative tap position on canvas → normalized marker coordinates.
Offset tapToNormalizedMarker(Offset local, Size canvasSize) {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) {
    return Offset.zero;
  }
  return Offset(
    (local.dx / canvasSize.width).clamp(0.0, 1.0),
    (local.dy / canvasSize.height).clamp(0.0, 1.0),
  );
}

/// Normalized marker coordinates → pixel center on canvas.
Offset normalizedMarkerToPixel(Offset normalized, Size canvasSize) {
  return Offset(
    normalized.dx * canvasSize.width,
    normalized.dy * canvasSize.height,
  );
}

/// Pixel center of a (possibly label-offset) seal label on the canvas.
Offset labelCenterPixel({
  required double x,
  required double y,
  double? offsetX,
  double? offsetY,
  required Size canvasSize,
}) {
  return Offset(
    (x + (offsetX ?? 0)) * canvasSize.width,
    (y + (offsetY ?? 0)) * canvasSize.height,
  );
}

/// Converts a drag delta in canvas pixels to a normalized offset delta.
Offset dragDeltaToNormalizedOffset(Offset deltaPx, Size canvasSize) {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) return Offset.zero;
  return Offset(deltaPx.dx / canvasSize.width, deltaPx.dy / canvasSize.height);
}

/// Matrix to center the viewer on a normalized marker position.
Matrix4 focusTransformForMarker({
  required double x,
  required double y,
  required Size canvasSize,
  double scale = 2.0,
}) {
  final px = x * canvasSize.width;
  final py = y * canvasSize.height;
  return Matrix4.identity()
    ..translate(
      canvasSize.width / 2 - px * scale,
      canvasSize.height / 2 - py * scale,
    )
    ..scale(scale);
}
