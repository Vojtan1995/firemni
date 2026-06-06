import 'dart:io';

import 'package:flutter/material.dart';
import '../core/design_tokens.dart';
import 'photo_fullscreen_viewer.dart';

class PhotoThumbnail extends StatelessWidget {
  const PhotoThumbnail({
    super.key,
    required this.image,
    this.onTap,
    this.onDelete,
    this.size = 100,
    this.borderRadius = AppRadius.sm,
    this.enableFullscreenOnTap = true,
  });

  final ImageProvider image;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final double size;
  final double borderRadius;
  final bool enableFullscreenOnTap;

  void _handleTap(BuildContext context) {
    if (onTap != null) {
      onTap!();
    } else if (enableFullscreenOnTap) {
      showPhotoFullscreen(context, image: image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canTap = onTap != null || enableFullscreenOnTap;

    return GestureDetector(
      onTap: canTap ? () => _handleTap(context) : null,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
          if (onDelete != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.bgPrimary.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: AppColors.textPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Convenience wrapper for local file paths.
class PhotoThumbnailFile extends StatelessWidget {
  const PhotoThumbnailFile({
    super.key,
    required this.path,
    this.onTap,
    this.onDelete,
    this.size = 100,
  });

  final String path;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PhotoThumbnail(
      image: FileImage(File(path)),
      onTap: onTap,
      onDelete: onDelete,
      size: size,
    );
  }
}
