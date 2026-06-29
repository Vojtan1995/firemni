import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';

class ChipSelector extends StatelessWidget {
  const ChipSelector({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.allowCustom = false,
    this.labelFor,
    this.emphasize = false,
  });

  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool allowCustom;

  /// Optional mapping from internal option value to a display label.
  final String Function(String)? labelFor;

  /// Zvýrazní název kategorie (barva + podtržení) — pro klíčové sekce formuláře.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: emphasize
              ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accent,
                  )
              : Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            ...options.map((o) {
              final isSelected = selected == o;
              return ChoiceChip(
                label: Text(labelFor != null ? labelFor!(o) : o),
                selected: isSelected,
                onSelected: (_) => onSelected(o),
                // Kompaktnější chipy — nižší výška, menší tap padding.
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selectedColor: AppColors.accent.withValues(alpha: 0.2),
                backgroundColor: AppColors.bgSecondary,
                labelStyle: TextStyle(
                  color: isSelected ? AppColors.accent : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                side: BorderSide(
                  color: isSelected ? AppColors.accent : AppColors.border,
                ),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
              );
            }),
            if (allowCustom)
              ActionChip(
                label: const Text('Vlastní'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: AppColors.bgSecondary,
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                onPressed: () async {
                  final v = await showDialog<String>(
                    context: context,
                    builder: (c) {
                      final ctrl = TextEditingController();
                      return AlertDialog(
                        title: Text('Vlastní – $label'),
                        content: TextField(controller: ctrl),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zrušit')),
                          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('OK')),
                        ],
                      );
                    },
                  );
                  if (v != null && v.isNotEmpty) onSelected(v);
                },
              ),
          ],
        ),
      ],
    );
  }
}
