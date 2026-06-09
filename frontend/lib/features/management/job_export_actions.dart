import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../reports/export_service.dart';

Future<void> exportJobPackage(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required String projectNumber,
  required String format,
}) async {
  final label = format.toUpperCase();
  try {
    final res = await ref.read(dioProvider).get(
      '/api/jobs/$jobId/export/$format',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = normalizeExportBytes(res.data, exportLabel: label);
    await saveExportFile(
      bytes: bytes,
      fileName: 'zakazka-$projectNumber',
      extension: format,
      exportLabel: 'Export zakázky ($label)',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export zakázky $projectNumber ($label) uložen')),
    );
  } on ExportSaveCancelled {
    return;
  } on DioException catch (e) {
    if (!context.mounted) return;
    final msg = e.response?.data is Map
        ? (e.response!.data as Map)['message'] ?? (e.response!.data as Map)['error']
        : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg?.toString() ?? 'Export selhal')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export selhal: $e')),
    );
  }
}

void showJobExportMenu(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required String projectNumber,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Export PDF'),
            subtitle: const Text('Patra, ucpávky, soupisy, historie, náhledy fotek'),
            onTap: () {
              Navigator.pop(ctx);
              exportJobPackage(
                context,
                ref,
                jobId: jobId,
                projectNumber: projectNumber,
                format: 'pdf',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export CSV'),
            subtitle: const Text('Strukturovaný export celé zakázky'),
            onTap: () {
              Navigator.pop(ctx);
              exportJobPackage(
                context,
                ref,
                jobId: jobId,
                projectNumber: projectNumber,
                format: 'csv',
              );
            },
          ),
        ],
      ),
    ),
  );
}
