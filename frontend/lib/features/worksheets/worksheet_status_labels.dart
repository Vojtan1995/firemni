import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';

/// České popisky a barvy stavů soupisu – zrcadlí backend `STATUS_LABELS`
/// (worksheet.service.ts). Stejný vzor jako marker_colors.dart pro ucpávky.
String worksheetStatusLabel(String? status) => switch (status) {
      'draft' => 'Rozpracovaný',
      'submitted' => 'Odevzdaný',
      'reviewed' => 'Schválený',
      'ready_for_invoice' => 'Připravený k fakturaci',
      'invoiced' => 'Vyfakturovaný',
      _ => status ?? '',
    };

Color worksheetStatusColor(String? status) => switch (status) {
      'draft' => AppColors.info,
      'submitted' => AppColors.warning,
      'reviewed' => AppColors.success,
      'ready_for_invoice' => AppColors.accent,
      'invoiced' => AppColors.textMuted,
      _ => AppColors.textMuted,
    };
