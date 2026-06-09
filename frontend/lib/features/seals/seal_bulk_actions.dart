import 'package:flutter/material.dart';

/// Potvrzení hromadné akce s počtem vybraných položek.
Future<bool> confirmBulkAction(
  BuildContext context, {
  required String title,
  required int count,
  String? message,
  String confirmLabel = 'Potvrdit',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(
        message ?? 'Opravdu provést akci u $count vybraných ucpávek?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptBulkReturnComment(BuildContext context) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Vrátit k opravě'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(labelText: 'Komentář (povinný)'),
        maxLines: 3,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Potvrdit'),
        ),
      ],
    ),
  );
  return result;
}

void showBulkResultSnackBar(
  BuildContext context, {
  required int succeeded,
  required int failed,
  required String actionLabel,
}) {
  final text = failed == 0
      ? '$actionLabel: $succeeded úspěšně'
      : '$actionLabel: $succeeded úspěšně, $failed selhalo';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Map<String, dynamic>? parseBulkResponse(Map<String, dynamic>? data) {
  if (data == null) return null;
  final succeeded = data['updated'] as int? ??
      data['moved'] as int? ??
      (data['seals'] as List?)?.length ??
      0;
  final failed = data['failed'] as int? ??
      (data['errors'] as List?)?.length ??
      0;
  return {'succeeded': succeeded, 'failed': failed};
}
