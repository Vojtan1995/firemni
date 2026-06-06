import 'package:flutter/material.dart';

/// Design tokens for UNIFAST Ucpávky dark theme.
abstract final class AppColors {
  static const bgPrimary = Color(0xFF0D0D0D);
  static const bgSecondary = Color(0xFF171717);
  static const surface = Color(0xFF1E1E1E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA0A0A0);
  static const textMuted = Color(0xFF666666);
  static const accent = Color(0xFFE10600);
  static const accentHover = Color(0xFFFF2A23);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFDC2626);
  static const info = Color(0xFF3B82F6);
  static const border = Color(0xFF2A2A2A);
}

abstract final class AppRadius {
  static const sm = 12.0;
  static const md = 14.0;
  static const lg = 16.0;
  static const xl = 20.0;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppShadows {
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}
