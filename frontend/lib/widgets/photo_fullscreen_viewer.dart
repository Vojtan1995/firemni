import 'package:flutter/material.dart';
import '../core/design_tokens.dart';

/// Opens a fullscreen photo viewer with pinch-zoom and optional gallery swipe.
Future<void> showPhotoFullscreen(
  BuildContext context, {
  required ImageProvider image,
  List<ImageProvider>? gallery,
  int initialIndex = 0,
}) {
  final images = gallery ?? [image];
  final start = initialIndex.clamp(0, images.length - 1);

  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (ctx, _, __) => _PhotoFullscreenPage(
        images: images,
        initialIndex: start,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _PhotoFullscreenPage extends StatefulWidget {
  const _PhotoFullscreenPage({
    required this.images,
    required this.initialIndex,
  });

  final List<ImageProvider> images;
  final int initialIndex;

  @override
  State<_PhotoFullscreenPage> createState() => _PhotoFullscreenPageState();
}

class _PhotoFullscreenPageState extends State<_PhotoFullscreenPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCounter = widget.images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => _ZoomablePhoto(image: widget.images[i]),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: AppColors.textPrimary, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          if (showCounter)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.images.length}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatelessWidget {
  const _ZoomablePhoto({required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5,
      child: Center(
        child: Image(
          image: image,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
