import 'package:flutter/material.dart';
import '../core/design_tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.style = SectionHeaderStyle.h2,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final SectionHeaderStyle style;

  @override
  Widget build(BuildContext context) {
    final titleStyle = style == SectionHeaderStyle.h2
        ? Theme.of(context).textTheme.headlineMedium
        : Theme.of(context).textTheme.titleLarge;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

enum SectionHeaderStyle { h2, h3 }
