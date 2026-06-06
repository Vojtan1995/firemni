import 'package:flutter/material.dart';
import '../core/design_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.margin,
    this.color,
    this.borderColor,
    this.showChevron = true,
    this.padding,
    this.child,
  });

  final Widget? leading;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final bool showChevron;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child ??
        Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ] else if (showChevron && onTap != null)
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        );

    return Padding(
      padding: margin ?? const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: color ?? AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: borderColor != null
              ? BorderSide(color: borderColor!)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              boxShadow: AppShadows.card,
            ),
            padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
            child: content,
          ),
        ),
      ),
    );
  }
}
