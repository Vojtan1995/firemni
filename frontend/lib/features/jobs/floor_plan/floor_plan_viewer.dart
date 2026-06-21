import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'seal_marker_widget.dart';

const double kFloorPlanMinScale = 0.5;
const double kFloorPlanMaxScale = 12.0;

/// Maximální delší strana vyrenderované PDF bitmapy v px. Strop chrání RAM na
/// mobilu — i při velkém zoomu se nikdy nerenderuje extrémně velký obraz.
const double kPdfMaxRenderDim = 4000.0;

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
                    )
                  : Image.memory(
                      widget.bytes,
                      width: w,
                      height: h,
                      fit: BoxFit.fill,
                      // medium dává hladší interpolaci při přiblížení než
                      // none; originální bitmapa zůstává nezměněná.
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
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
                                reviewStatus: m['reviewStatus'] as String?,
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
  });

  final PdfDocumentRef documentRef;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Keep PDF rendering independent from the current InteractiveViewer zoom.
    // Zooming scales this page image instead of triggering a full-page rerender
    // for every zoom bucket.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    double renderW = width * dpr;
    double renderH = height * dpr;
    final longest = math.max(renderW, renderH);
    if (longest > kPdfMaxRenderDim) {
      final k = kPdfMaxRenderDim / longest;
      renderW *= k;
      renderH *= k;
    }
    return PdfDocumentViewBuilder(
      documentRef: documentRef,
      builder: (context, document) {
        if (document == null) {
          return const ColoredBox(
            color: Colors.white,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return PdfPageView(
          document: document,
          pageNumber: 1,
          maximumDpi: 2400,
          decoration: const BoxDecoration(color: Colors.white),
          pageSizeCallback: (_, __) => Size(renderW, renderH),
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
  }
}
