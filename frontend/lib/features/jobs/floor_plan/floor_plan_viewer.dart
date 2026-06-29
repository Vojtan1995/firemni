import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'seal_marker_widget.dart';

const double kFloorPlanMinScale = 0.5;
const double kFloorPlanMaxScale = 40.0;

/// Maximální delší strana vyrenderované PDF bitmapy v px. Strop chrání RAM na
/// mobilu i rychlost — i při velkém zoomu se nikdy nerenderuje extrémně velký
/// obraz. Běžný zoom (buckety do 8×) zůstává ostrý, jen extrémní max-zoom je
/// o něco méně ostrý výměnou za výrazně rychlejší načtení/render.
const double kPdfMaxRenderDim = 6000.0;
const List<double> kPdfRenderScaleBuckets = [1, 1.5, 2, 3, 4, 6, 8];

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
const double kRasterZoomHeadroom = 6.0;

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
    this.markerSizeFactor = 1.0,
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

  /// Ruční násobič velikosti značek (tlačítka +/−), nad automatickým
  /// škálováním podle zoomu. 1.0 = výchozí.
  final double markerSizeFactor;

  bool get isPdf => mimeType.toLowerCase().contains('pdf');

  @override
  State<FloorPlanViewer> createState() => _FloorPlanViewerState();
}

class _FloorPlanViewerState extends State<FloorPlanViewer> {
  late PdfDocumentRef _pdfDocumentRef;

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
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: widget.transformationController,
      minScale: kFloorPlanMinScale,
      maxScale: kFloorPlanMaxScale,
      panEnabled: true,
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
                        final markerScale = markerScaleForViewer(viewerScale) *
                            widget.markerSizeFactor;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: widget.markers.map((m) {
                            final x = (m['x'] as num).toDouble();
                            final y = (m['y'] as num).toDouble();
                            final sealId = m['sealId'] as String;
                            final pending = m['pending'] == true;
                            final highlighted =
                                pending || widget.highlightSealId == sealId;
                            final topLeft = sealMarkerTopLeft(
                              x: x,
                              y: y,
                              canvasSize: canvasSize,
                              scale: markerScale,
                              highlighted: highlighted,
                            );
                            return Positioned(
                              left: topLeft.dx,
                              top: topLeft.dy,
                              child: SealMarkerWidget(
                                sealNumber: m['sealNumber'] as String? ?? '',
                                status: m['status'] as String? ?? 'draft',
                                scale: markerScale,
                                highlighted: highlighted,
                                onTap: widget.onMarkerTap != null && !pending
                                    ? () => widget.onMarkerTap!(m)
                                    : null,
                              ),
                            );
                          }).toList(),
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
