import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light {
    const primary = Color(0xFF1565C0);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: primary),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  static Color statusColor(String status, {bool conflict = false}) {
    if (conflict) return Colors.red;
    switch (status) {
      case 'draft':
        return Colors.amber;
      case 'checked':
        return Colors.green;
      case 'invoiced':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
