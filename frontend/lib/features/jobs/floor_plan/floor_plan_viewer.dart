import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'floor_drawing_upload.dart' show labelCenterPixel, dragDeltaToNormalizedOffset;
import 'seal_marker_widget.dart';

const double kFloorPlanMinScale = 0.5;
const double kFloorPlanMaxScale = 24.0;

/// Maximální delší strana vyrenderované PDF bitmapy v px. Strop chrání RAM na
/// mobilu i rychlost — i při velkém zoomu se nikdy nerenderuje extrémně velký
/// obraz. Běžný zoom (buckety do 4×) zůstává ostrý, jen extrémní max-zoom je
/// o něco méně ostrý výměnou za výrazně rychlejší načtení/render.
const double kPdfMaxRenderDim = 4000.0;
const List<double> kPdfRenderScaleBuckets = [1, 1.5, 2, 3, 4];

double floorPlanPdfRenderBucket(double viewerScale) {
  if (!viewerScale.isFinite || viewerScale <= 1) return 1;
  for (final bucket in kPdfRenderScaleBuckets) {
    if (viewerScale <= bucket) return bucket;
  }
  return kPdfRenderScaleBuckets.last;
}

Size floorPlanPdfRenderSize({
  required double width,
  required double height,
  required double devicePixelRatio,
  required double viewerScale,
  double maxRenderDim = kPdfMaxRenderDim,
}) {
  final bucket = floorPlanPdfRenderBucket(viewerScale);
  double renderW = width * devicePixelRatio * bucket;
  double renderH = height * devicePixelRatio * bucket;
  final longest = math.max(renderW, renderH);
  if (longest > maxRenderDim) {
    final k = maxRenderDim / longest;
    renderW *= k;
    renderH *= k;
  }
  return Size(renderW, renderH);
}

/// Statický strop pro [Image.memory.cacheWidth/cacheHeight] u rastrových
/// výkresů (PNG/JPG). Na rozdíl od PDF se rastr nepřerenderovává podle zoomu
/// (InteractiveViewer jen transformuje hotovou bitmapu), proto stačí jedno
/// pevné rozlišení — dost ostré i pro přiblížení, ale bez dekódování celého
/// velkého zdrojového souboru (až 50 MB) v plné velikosti.
const double kRasterZoomHeadroom = 4.0;

Size floorPlanRasterCacheSize({
  required double width,
  required double height,
  required double devicePixelRatio,
  required int intrinsicWidth,
  required int intrinsicHeight,
  double maxRenderDim = kPdfMaxRenderDim,
}) {
  double renderW = math.min(
    width * devicePixelRatio * kRasterZoomHeadroom,
    intrinsicWidth.toDouble(),
  );
  double renderH = math.min(
    height * devicePixelRatio * kRasterZoomHeadroom,
    intrinsicHeight.toDouble(),
  );
  final longest = math.max(renderW, renderH);
  if (longest > maxRenderDim) {
    final k = maxRenderDim / longest;
    renderW *= k;
    renderH *= k;
  }
  return Size(renderW, renderH);
}

class FloorPlanViewer extends StatefulWidget {
  const FloorPlanViewer({
    super.key,
    required this.bytes,
    required this.mimeType,
    required this.intrinsicWidth,
    required this.intrinsicHeight,
    required this.transformationController,
    required this.viewerScale,
    required this.markers,
    required this.onCanvasSizeChanged,
    this.onTapPlan,
    this.onMarkerTap,
    this.highlightSealId,
    this.labelEditMode = false,
    this.onLabelOffsetChanged,
  });

  final Uint8List bytes;
  final String mimeType;
  final int intrinsicWidth;
  final int intrinsicHeight;
  final TransformationController transformationController;

  /// Aktuální zoom jako [ValueListenable] – při změně zoomu se překreslí JEN
  /// vrstva markerů (ValueListenableBuilder), nikoli PDF/obrázek ani celý strom.
  final ValueListenable<double> viewerScale;
  final List<Map<String, dynamic>> markers;
  final ValueChanged<Size> onCanvasSizeChanged;
  final void Function(Offset local, Size canvasSize)? onTapPlan;
  final void Function(Map<String, dynamic> marker)? onMarkerTap;
  final String? highlightSealId;

  /// Když true, štítky se zobrazují s číselným popiskem odtažitelným od
  /// přesné pozice ucpávky (tečka + odkazová čára) a pan výkresu je vypnutý,
  /// aby tažení štítku nesoupeřilo s gesty InteractiveViewer.
  final bool labelEditMode;

  /// Voláno po dokončení tažení štítku s výsledným normalizovaným offsetem.
  final void Function(String sealId, double offsetX, double offsetY)?
      onLabelOffsetChanged;

  bool get isPdf => mimeType.toLowerCase().contains('pdf');

  @override
  State<FloorPlanViewer> createState() => _FloorPlanViewerState();
}

class _FloorPlanViewerState extends State<FloorPlanViewer> {
  late PdfDocumentRef _pdfDocumentRef;

  /// Živý náhled tažení štítku, dokud worker neuvolní prst — přepisuje
  /// uložený labelOffset jen pro vykreslení, ne pro data ve [widget.markers].
  final Map<String, Offset> _dragOverrides = {};

  @override
  void initState() {
    super.initState();
    _pdfDocumentRef = PdfDocumentRefData(
      widget.bytes,
      sourceName: 'floor-${widget.bytes.hashCode}',
    );
  }

  @override
  void didUpdateWidget(covariant FloorPlanViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      _pdfDocumentRef = PdfDocumentRefData(
        widget.bytes,
        sourceName: 'floor-${widget.bytes.hashCode}',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.transformationController.value = Matrix4.identity();
        }
      });
    }
    if (_dragOverrides.isNotEmpty) {
      final bySealId = {
        for (final m in widget.markers) m['sealId'] as String: m,
      };
      _dragOverrides.removeWhere((sealId, override) {
        final m = bySealId[sealId];
        if (m == null) return true;
        final ox = (m['labelOffsetX'] as num?)?.toDouble() ?? 0;
        final oy = (m['labelOffsetY'] as num?)?.toDouble() ?? 0;
        return (ox - override.dx).abs() < 0.0001 &&
            (oy - override.dy).abs() < 0.0001;
      });
    }
  }

  void _onLabelPanStart(String sealId, double baseOffsetX, double baseOffsetY) {
    setState(() {
      _dragOverrides[sealId] = Offset(baseOffsetX, baseOffsetY);
    });
  }

  void _onLabelPanUpdate(String sealId, Offset deltaPx, Size canvasSize) {
    final deltaNorm = dragDeltaToNormalizedOffset(deltaPx, canvasSize);
    setState(() {
      final current = _dragOverrides[sealId] ?? Offset.zero;
      _dragOverrides[sealId] = Offset(
        (current.dx + deltaNorm.dx).clamp(-1.0, 1.0),
        (current.dy + deltaNorm.dy).clamp(-1.0, 1.0),
      );
    });
  }

  void _onLabelPanEnd(String sealId) {
    final offset = _dragOverrides[sealId];
    if (offset != null) {
      widget.onLabelOffsetChanged?.call(sealId, offset.dx, offset.dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: widget.transformationController,
      minScale: kFloorPlanMinScale,
      maxScale: kFloorPlanMaxScale,
      // V režimu úpravy popisků je pan vypnutý, aby tažení štítku
      // nesoupeřilo s gestem posunu výkresu.
      panEnabled: !widget.labelEditMode,
      scaleEnabled: true,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final aspect = widget.intrinsicWidth / widget.intrinsicHeight;
            final maxW = constraints.maxWidth;
            final maxH = constraints.maxHeight;
            double w = maxW;
            double h = w / aspect;
            if (h > maxH) {
              h = maxH;
              w = h * aspect;
            }
            final canvasSize = Size(w, h);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onCanvasSizeChanged(canvasSize);
            });

            // Podklad (PDF/obrázek) je v RepaintBoundary a NEzávisí na zoomu,
            // takže se při zoomování nerasterizuje ani nerebuilduje.
            final background = RepaintBoundary(
              child: widget.isPdf
                  ? _PdfCanvas(
                      documentRef: _pdfDocumentRef,
                      width: w,
                      height: h,
                      viewerScale: widget.viewerScale,
                    )
                  : Builder(builder: (context) {
                      final cacheSize = floorPlanRasterCacheSize(
                        width: w,
                        height: h,
                        devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
                        intrinsicWidth: widget.intrinsicWidth,
                        intrinsicHeight: widget.intrinsicHeight,
                      );
                      return Image.memory(
                        widget.bytes,
                        width: w,
                        height: h,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        cacheWidth: cacheSize.width.round(),
                        cacheHeight: cacheSize.height.round(),
                      );
                    }),
            );

            return GestureDetector(
              onTapUp: widget.onTapPlan != null
                  ? (d) => widget.onTapPlan!(d.localPosition, canvasSize)
                  : null,
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    background,
                    // Jen tato vrstva reaguje na změnu zoomu.
                    ValueListenableBuilder<double>(
                      valueListenable: widget.viewerScale,
                      builder: (context, viewerScale, _) {
                        final markerScale = markerScaleForViewer(viewerScale);
                        final lines = <_LeaderLine>[];
                        final children = <Widget>[];

                        for (final m in widget.markers) {
                          final x = (m['x'] as num).toDouble();
                          final y = (m['y'] as num).toDouble();
                          final sealId = m['sealId'] as String;
                          final pending = m['pending'] == true;
                          final highlighted =
                              pending || widget.highlightSealId == sealId;
                          final status = m['status'] as String? ?? 'draft';

                          final override = _dragOverrides[sealId];
                          final baseOffsetX =
                              (m['labelOffsetX'] as num?)?.toDouble() ?? 0;
                          final baseOffsetY =
                              (m['labelOffsetY'] as num?)?.toDouble() ?? 0;
                          final offsetX = override?.dx ?? baseOffsetX;
                          final offsetY = override?.dy ?? baseOffsetY;
                          final hasOffset = offsetX != 0 || offsetY != 0;

                          final pointPixel = Offset(
                            x * canvasSize.width,
                            y * canvasSize.height,
                          );
                          final labelPixel = labelCenterPixel(
                            x: x,
                            y: y,
                            offsetX: offsetX,
                            offsetY: offsetY,
                            canvasSize: canvasSize,
                          );

                          if (hasOffset) {
                            lines.add(_LeaderLine(pointPixel, labelPixel));
                            final dotSize =
                                (kSealPointDotBaseSize * markerScale)
                                    .clamp(3.0, 10.0);
                            Widget dot = SealPointDot(
                              status: status,
                              scale: markerScale,
                            );
                            if (widget.onMarkerTap != null && !pending) {
                              dot = GestureDetector(
                                onTap: () => widget.onMarkerTap!(m),
                                child: dot,
                              );
                            }
                            children.add(Positioned(
                              left: pointPixel.dx - dotSize / 2,
                              top: pointPixel.dy - dotSize / 2,
                              child: dot,
                            ));
                          }

                          final labelDims = sealMarkerDimensions(
                            markerScale,
                            highlighted: highlighted,
                          );
                          final labelTopLeft = hasOffset
                              ? Offset(
                                  labelPixel.dx - labelDims.size / 2,
                                  labelPixel.dy - labelDims.size / 2,
                                )
                              : sealMarkerTopLeft(
                                  x: x,
                                  y: y,
                                  canvasSize: canvasSize,
                                  scale: markerScale,
                                  highlighted: highlighted,
                                );

                          Widget label = SealMarkerWidget(
                            sealNumber: m['sealNumber'] as String? ?? '',
                            status: status,
                            scale: markerScale,
                            highlighted: highlighted,
                            onTap: widget.onMarkerTap != null && !pending
                                ? () => widget.onMarkerTap!(m)
                                : null,
                          );

                          if (widget.labelEditMode && !pending) {
                            label = GestureDetector(
                              onPanStart: (_) => _onLabelPanStart(
                                sealId,
                                baseOffsetX,
                                baseOffsetY,
                              ),
                              onPanUpdate: (d) => _onLabelPanUpdate(
                                sealId,
                                d.delta,
                                canvasSize,
                              ),
                              onPanEnd: (_) => _onLabelPanEnd(sealId),
                              child: label,
                            );
                          }

                          children.add(Positioned(
                            left: labelTopLeft.dx,
                            top: labelTopLeft.dy,
                            child: label,
                          ));
                        }

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CustomPaint(
                              size: canvasSize,
                              painter:
                                  _LeaderLinePainter(lines, markerScale),
                            ),
                            ...children,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LeaderLine {
  const _LeaderLine(this.from, this.to);
  final Offset from;
  final Offset to;
}

/// Tenké odkazové čáry mezi přesnou pozicí ucpávky a odtaženým štítkem.
class _LeaderLinePainter extends CustomPainter {
  const _LeaderLinePainter(this.lines, this.scale);

  final List<_LeaderLine> lines;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFF555555)
      ..strokeWidth = (1.0 * scale).clamp(0.4, 1.5)
      ..style = PaintingStyle.stroke;
    for (final line in lines) {
      canvas.drawLine(line.from, line.to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LeaderLinePainter oldDelegate) {
    return !identical(oldDelegate.lines, lines) || oldDelegate.scale != scale;
  }
}

class _PdfCanvas extends StatelessWidget {
  const _PdfCanvas({
    required this.documentRef,
    required this.width,
    required this.height,
    required this.viewerScale,
  });

  final PdfDocumentRef documentRef;
  final double width;
  final double height;
  final ValueListenable<double> viewerScale;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return PdfDocumentViewBuilder(
      documentRef: documentRef,
      builder: (context, document) {
        if (document == null) {
          return const ColoredBox(
            color: Colors.white,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ValueListenableBuilder<double>(
          valueListenable: viewerScale,
          builder: (context, scale, _) {
            final renderSize = floorPlanPdfRenderSize(
              width: width,
              height: height,
              devicePixelRatio: dpr,
              viewerScale: scale,
            );
            return PdfPageView(
              document: document,
              pageNumber: 1,
              maximumDpi: 1200,
              decoration: const BoxDecoration(color: Colors.white),
              pageSizeCallback: (_, __) => renderSize,
              decorationBuilder: (context, pageSize, page, pageImage) {
                return SizedBox(
                  width: width,
                  height: height,
                  child: pageImage != null
                      ? FittedBox(
                          fit: BoxFit.fill,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: pageSize.width,
                            height: pageSize.height,
                            child: pageImage,
                          ),
                        )
                      : const ColoredBox(color: Colors.white),
                );
              },
            );
          },
        );
      },
    );
  }
}
