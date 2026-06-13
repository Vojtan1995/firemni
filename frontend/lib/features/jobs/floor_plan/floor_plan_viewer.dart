import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'seal_marker_widget.dart';

const double kFloorPlanMinScale = 0.5;
const double kFloorPlanMaxScale = 12.0;
const double kPdfRenderScaleFactor = 12.0;

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
  final double viewerScale;
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

            final markerScale = markerScaleForViewer(widget.viewerScale);
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
                    if (widget.isPdf)
                      _PdfCanvas(
                        documentRef: _pdfDocumentRef,
                        width: w,
                        height: h,
                      )
                    else
                      Image.memory(
                        widget.bytes,
                        width: w,
                        height: h,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.none,
                        gaplessPlayback: true,
                      ),
                    ...widget.markers.map((m) {
                      final x = (m['x'] as num).toDouble();
                      final y = (m['y'] as num).toDouble();
                      final sealId = m['sealId'] as String;
                      final size = kSealMarkerBaseSize * markerScale;
                      return Positioned(
                        left: x * w - size / 2,
                        top: y * h - size / 2,
                        child: SealMarkerWidget(
                          sealNumber: m['sealNumber'] as String? ?? '',
                          status: m['status'] as String? ?? 'draft',
                          reviewStatus: m['reviewStatus'] as String?,
                          scale: markerScale,
                          highlighted: widget.highlightSealId == sealId,
                          onTap: widget.onMarkerTap != null
                              ? () => widget.onMarkerTap!(m)
                              : null,
                        ),
                      );
                    }),
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
          maximumDpi: 1200,
          decoration: const BoxDecoration(color: Colors.white),
          pageSizeCallback: (_, __) => Size(
            width * kPdfRenderScaleFactor,
            height * kPdfRenderScaleFactor,
          ),
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
