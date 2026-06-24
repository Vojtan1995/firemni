import 'package:flutter/material.dart';
import '../../../core/design_tokens.dart';

Color markerColorForSeal({
  required String status,
}) {
  switch (status) {
    case 'draft':
      return AppColors.error;
    case 'checked':
      return AppColors.success;
    case 'invoiced':
      return AppColors.textMuted;
    default:
      return AppColors.info;
  }
}

String markerStatusLabel({
  required String status,
}) {
  switch (status) {
    case 'draft':
      return 'Rozpracováno';
    case 'checked':
      return 'Zkontrolováno';
    case 'invoiced':
      return 'Fakturováno';
    default:
      return status;
  }
}
