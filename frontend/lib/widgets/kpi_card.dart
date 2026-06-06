import 'package:flutter/material.dart';
import '../core/design_tokens.dart';

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.progress,
    this.accentColor,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final double? progress;
  final Color? accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.accent;

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (icon != null)
                Icon(icon, size: 18, color: accent),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: AppRadius.smAll,
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 6,
                backgroundColor: AppColors.bgSecondary,
                color: accent,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: card,
      ),
    );
  }
}
