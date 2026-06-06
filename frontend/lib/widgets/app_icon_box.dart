import 'package:flutter/material.dart';
import '../core/design_tokens.dart';

/// Icon container used in menu cards and list items.
class AppIconBox extends StatelessWidget {
  const AppIconBox({
    super.key,
    required this.icon,
    this.color,
    this.backgroundColor,
    this.size = 44,
  });

  final IconData icon;
  final Color? color;
  final Color? backgroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.accent.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Icon(
        icon,
        color: color ?? AppColors.accent,
        size: size * 0.5,
      ),
    );
  }
}
