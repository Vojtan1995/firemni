import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'marker_colors.dart';

const double kSealMarkerBaseSize = 18;

/// Cílová velikost značky NA OBRAZOVCE (logické px), nezávislá na zoomu
/// výkresu. Klesá s přiblížením, aby se na stěnu vešlo i 5+ ucpávek těsně
/// vedle sebe — čím větší zoom, tím menší značka.
double _onScreenMarkerSize(double viewerScale) {
  final v = viewerScale.isFinite && viewerScale > 0 ? viewerScale : 1.0;
  final raw = 16.0 / math.pow(v, 0.35);
  return raw.clamp(6.0, 16.0);
}

/// Vrací škálu pro [sealMarkerDimensions] tak, aby výsledná velikost na
/// obrazovce (po vynásobení transformací [InteractiveViewer]ru, tedy
/// `velikost * viewerScale`) odpovídala [_onScreenMarkerSize]. Bez horního ani
/// dolního px-clampu na logické velikosti — ten dřív způsoboval nafouknutí
/// značek při velkém zoomu.
double markerScaleForViewer(double viewerScale) {
  final v = viewerScale.isFinite && viewerScale > 0 ? viewerScale : 1.0;
  final onScreen = _onScreenMarkerSize(v);
  return onScreen / (kSealMarkerBaseSize * v);
}

({
  double size,
  double fontSize,
  double borderWidth,
  double highlightBorderWidth,
  double shadowBlur,
  double padding,
}) sealMarkerDimensions(double scale, {bool highlighted = false}) {
  // Zvýrazněná (aktivní/čekající) značka je o trochu větší než ostatní při
  // stejném zoomu, ať je dohledatelná, ale dál se zmenšuje se zoomem stejně
  // jako ostatní (žádný absolutní px floor).
  final size = kSealMarkerBaseSize * scale * (highlighted ? 1.3 : 1.0);
  final fontSize = size * (7 / kSealMarkerBaseSize);
  final borderWidth = size * (1.5 / kSealMarkerBaseSize);
  final highlightBorderWidth = size * (3.0 / kSealMarkerBaseSize);
  final shadowBlur = size * ((highlighted ? 8.0 : 2.0) / kSealMarkerBaseSize);
  final padding = size * (1.0 / kSealMarkerBaseSize);
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
