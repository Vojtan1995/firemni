import 'package:flutter/material.dart';
import 'marker_colors.dart';

const double kSealMarkerBaseSize = 18;

double markerScaleForViewer(double viewerScale) =>
    (1 / viewerScale).clamp(0.08, 2.0);

({
  double size,
  double fontSize,
  double borderWidth,
  double highlightBorderWidth,
  double shadowBlur,
  double padding,
}) sealMarkerDimensions(double scale, {bool highlighted = false}) {
  final size = (kSealMarkerBaseSize * scale).clamp(6.0, 26.0);
  final fontSize = (7 * scale).clamp(4.5, 9.0);
  final borderWidth = (1.5 * scale).clamp(0.5, 2.0);
  final highlightBorderWidth = (3.0 * scale).clamp(1.0, 3.0);
  final shadowBlur = highlighted
      ? (8.0 * scale).clamp(1.0, 8.0)
      : (2.0 * scale).clamp(0.5, 8.0);
  final padding = (1.0 * scale).clamp(0.0, 2.0);
  return (
    size: size,
    fontSize: fontSize,
    borderWidth: borderWidth,
    highlightBorderWidth: highlightBorderWidth,
    shadowBlur: shadowBlur,
    padding: padding,
  );
}

Offset sealMarkerTopLeft({
  required double x,
  required double y,
  required Size canvasSize,
  required double scale,
  bool highlighted = false,
}) {
  final dims = sealMarkerDimensions(scale, highlighted: highlighted);
  return Offset(
    x * canvasSize.width - dims.size / 2,
    y * canvasSize.height - dims.size / 2,
  );
}

class SealMarkerWidget extends StatelessWidget {
  const SealMarkerWidget({
    super.key,
    required this.sealNumber,
    required this.status,
    this.scale = 1,
    this.highlighted = false,
    this.onTap,
  });

  final String sealNumber;
  final String status;
  final double scale;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = markerColorForSeal(status: status);
    final dims = sealMarkerDimensions(scale, highlighted: highlighted);

    return GestureDetector(
      onTap: onTap,
      // Žádná animovaná prodleva při zoomu – marker se překresluje okamžitě.
      child: Container(
        width: dims.size,
        height: dims.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: highlighted ? Colors.yellow : Colors.white,
            width: highlighted ? dims.highlightBorderWidth : dims.borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: highlighted
                  ? Colors.yellow.withValues(alpha: 0.6)
                  : Colors.black45,
              blurRadius: dims.shadowBlur,
              offset: Offset(0, dims.shadowBlur * 0.5),
            ),
          ],
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.all(dims.padding),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            sealNumber,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: dims.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
