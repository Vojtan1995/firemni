import 'package:flutter/material.dart';
import '../../../core/design_tokens.dart';
import '../../../widgets/widgets.dart';

class PlacementStatsBanner extends StatelessWidget {
  const PlacementStatsBanner({
    super.key,
    required this.total,
    required this.placed,
    required this.unplaced,
    this.onShowUnplaced,
    this.onOk,
  });

  final int total;
  final int placed;
  final int unplaced;
  final VoidCallback? onShowUnplaced;
  final VoidCallback? onOk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.bgSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Celkem ucpávek: $total · Umístěno ve výkresu: $placed · Neumístěno: $unplaced',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (unplaced > 0 && onShowUnplaced != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppSecondaryButton(
              label: 'Zobrazit neumístěné',
              fullWidth: false,
              onPressed: onShowUnplaced,
            ),
          ],
          if (onOk != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppSecondaryButton(
              label: 'OK',
              fullWidth: false,
              onPressed: onOk,
            ),
          ],
        ],
      ),
    );
  }
}
