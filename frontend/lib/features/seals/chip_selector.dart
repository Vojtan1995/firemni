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
  });

  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool allowCustom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ...options.map((o) {
              final isSelected = selected == o;
              return ChoiceChip(
                label: Text(o),
                selected: isSelected,
                onSelected: (_) => onSelected(o),
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
