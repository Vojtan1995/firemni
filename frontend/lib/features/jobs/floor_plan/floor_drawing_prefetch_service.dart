import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../../database/database.dart';
import 'floor_drawing_download_service.dart';

/// Po online otevření zakázky stáhne metadata a soubory výkresů všech pater.
Future<void> prefetchJobFloorDrawings({
  required Dio dio,
  required AppDatabase db,
  required String jobId,
}) async {
  try {
    final res = await dio.get(
      '/api/sync/pull',
      queryParameters: {
        'jobId': jobId,
        'since': '1970-01-01T00:00:00.000Z',
      },
    );
    final data = res.data as Map<String, dynamic>;
    for (final d in (data['floorDrawings'] as List? ?? [])) {
      final m = d as Map<String, dynamic>;
      final floorId = m['floorId'] as String;
      await upsertFloorDrawingMetadata(
        db,
        floorId: floorId,
        jobId: jobId,
        meta: m,
      );
      await downloadFloorDrawingFile(
        dio: dio,
        db: db,
        jobId: jobId,
        floorId: floorId,
        meta: m,
      );
    }
  } catch (_) {
    // Fallback: projít patra a zkusit drawing endpoint per floor.
    final floors = await (db.select(db.localFloors)
          ..where((f) => f.jobId.equals(jobId) & f.deletedAt.isNull()))
        .get();
    for (final floor in floors) {
      try {
        final res = await dio.get(
          '/api/jobs/$jobId/floors/${floor.id}/drawing',
        );
        final drawing = (res.data as Map)['drawing'] as Map<String, dynamic>?;
        if (drawing == null) continue;
        await upsertFloorDrawingMetadata(
          db,
          floorId: floor.id,
          jobId: jobId,
          meta: drawing,
        );
        await downloadFloorDrawingFile(
          dio: dio,
          db: db,
          jobId: jobId,
          floorId: floor.id,
          meta: drawing,
        );
      } catch (_) {}
    }
  }
}
