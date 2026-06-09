import 'package:flutter/material.dart';

/// Potvrzení opuštění formuláře s neuloženými změnami.
Future<bool> confirmDiscardUnsavedChanges(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Neuložené změny'),
      content: const Text('Opravdu chcete odejít bez uložení?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Zůstat'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Odejít'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// [PopScope] pro formuláře — respektuje ESC (maybePop) i systémové zpět.
class UnsavedChangesPopScope extends StatelessWidget {
  const UnsavedChangesPopScope({
    super.key,
    required this.isDirty,
    required this.child,
  });

  final bool isDirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !isDirty) return;
        final leave = await confirmDiscardUnsavedChanges(context);
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}
