import 'package:flutter/material.dart';

Future<List<String>?> pickWorksheetWorkerIds(
  BuildContext context, {
  required List<Map<String, dynamic>> workers,
  List<String> initialSelected = const [],
}) async {
  if (workers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nejsou k dispozici žádní pracovníci')),
    );
    return null;
  }

  final selected = {...initialSelected};

  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Pracovníci v soupisu'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: workers.map((w) {
              final id = w['id'] as String;
              final name = w['displayName'] as String? ?? id;
              return CheckboxListTile(
                value: selected.contains(id),
                title: Text(name),
                onChanged: (checked) {
                  setDialogState(() {
                    if (checked == true) {
                      selected.add(id);
                    } else {
                      selected.remove(id);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(ctx, selected.toList()),
            child: const Text('Potvrdit'),
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> createWorksheetWithWorkers({
  required Future<Map<String, dynamic>> Function(Map<String, dynamic> body) postWorksheet,
  required String jobId,
  required List<String> workerIds,
}) async {
  return postWorksheet({
    'jobId': jobId,
    'workerIds': workerIds,
  });
}
