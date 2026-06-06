import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';

/// Vícenásobný výběr hodnot přes chipy (toggle).
class MultiChipSelector extends StatelessWidget {
  const MultiChipSelector({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.allowCustom = false,
  });

  final String label;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool allowCustom;

  List<String> get _displayOptions {
    final seen = <String>{};
    final out = <String>[];
    for (final o in options) {
      if (seen.add(o)) out.add(o);
    }
    for (final s in selected) {
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  void _toggle(String value) {
    final next = List<String>.from(selected);
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    onChanged(next);
  }

  Future<void> _addCustom(BuildContext context) async {
    final v = await showDialog<String>(
      context: context,
      builder: (c) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text('Vlastní – $label'),
          content: TextField(controller: ctrl, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zrušit')),
            TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK')),
          ],
        );
      },
    );
    if (v == null || v.isEmpty) return;
    if (selected.contains(v)) return;
    onChanged([...selected, v]);
  }

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
        if (selected.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Vybráno: ${selected.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ..._displayOptions.map((o) {
              final isSelected = selected.contains(o);
              return FilterChip(
                label: Text(o),
                selected: isSelected,
                onSelected: (_) => _toggle(o),
                selectedColor: AppColors.accent.withValues(alpha: 0.2),
                backgroundColor: AppColors.bgSecondary,
                checkmarkColor: AppColors.accent,
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
                onPressed: () => _addCustom(context),
              ),
          ],
        ),
      ],
    );
  }
}
