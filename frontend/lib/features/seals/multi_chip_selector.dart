import 'package:flutter/material.dart';

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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Vybráno: ${selected.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._displayOptions.map(
              (o) => FilterChip(
                label: Text(o),
                selected: selected.contains(o),
                onSelected: (_) => _toggle(o),
              ),
            ),
            if (allowCustom)
              ActionChip(
                label: const Text('Vlastní'),
                onPressed: () => _addCustom(context),
              ),
          ],
        ),
      ],
    );
  }
}
