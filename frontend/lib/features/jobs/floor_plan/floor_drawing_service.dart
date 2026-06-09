import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../reports/export_service.dart';
import 'floor_plan_filters.dart';

/// Export is not available for the active floor-plan filter (e.g. unplaced only).
class FloorDrawingExportUnsupported implements Exception {
  const FloorDrawingExportUnsupported();
}

Future<bool> pickAndUploadFloorDrawing({
  required Dio dio,
  required String jobId,
  required String floorId,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return false;
  final file = picked.files.first;
  if (file.bytes == null) return false;

  final form = FormData.fromMap({
    'drawing': MultipartFile.fromBytes(
      file.bytes!,
      filename: file.name,
    ),
  });
  await dio.post(
    '/api/jobs/$jobId/floors/$floorId/drawing',
    data: form,
  );
  return true;
}

Future<bool> confirmAndDeleteFloorDrawing({
  required BuildContext context,
  required Dio dio,
  required String jobId,
  required String floorId,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Smazat výkres'),
      content: const Text('Opravdu smazat výkres patra včetně značek?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Smazat'),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  await dio.delete('/api/jobs/$jobId/floors/$floorId/drawing');
  return true;
}

Future<String?> exportFloorDrawingPdf({
  required Dio dio,
  required String jobId,
  required String floorId,
  required String fileNameBase,
  FloorPlanFilterState filter = FloorPlanFilterState.allFilters,
  String? currentUserId,
}) async {
  final params = filter.toExportQueryParams(currentUserId: currentUserId);
  if (params == null) throw const FloorDrawingExportUnsupported();

  final res = await dio.get(
    '/api/jobs/$jobId/floors/$floorId/drawing/export/pdf',
    queryParameters: params.isEmpty ? null : params,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = normalizeExportBytes(res.data, exportLabel: 'PDF výkresu');
  return saveExportFile(
    bytes: bytes,
    fileName: fileNameBase,
    extension: 'pdf',
    exportLabel: 'PDF výkresu',
  );
}
