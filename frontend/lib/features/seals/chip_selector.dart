import 'package:flutter/material.dart';

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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...options.map((o) => ChoiceChip(
              label: Text(o),
              selected: selected == o,
              onSelected: (_) => onSelected(o),
            )),
            if (allowCustom)
              ActionChip(
                label: const Text('Vlastní'),
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
