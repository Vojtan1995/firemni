import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_drawing_download_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  test('changed drawing metadata clears cached markers on the floor', () async {
    final now = DateTime.now();
    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-1',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: '1',
            system: 'System',
            construction: 'Wall',
            location: 'A1',
            fireRating: 'EI 60',
            markerPlacementPending: const Value(false),
            updatedAt: now,
          ),
        );
    await db.into(db.localSealMarkers).insert(
          LocalSealMarkersCompanion.insert(
            sealId: 'seal-1',
            floorId: 'floor-1',
            sealNumber: '1',
            x: 0.25,
            y: 0.5,
            updatedAt: now,
          ),
        );

    await upsertFloorDrawingMetadata(
      db,
      floorId: 'floor-1',
      jobId: 'job-1',
      meta: {
        'filePath': 'old.png',
        'mimeType': 'image/png',
        'width': 100,
        'height': 100,
        'updatedAt': now.toIso8601String(),
      },
    );

    final changed = await upsertFloorDrawingMetadata(
      db,
      floorId: 'floor-1',
      jobId: 'job-1',
      meta: {
        'filePath': 'new.png',
        'mimeType': 'image/png',
        'width': 100,
        'height': 100,
        'updatedAt': now.add(const Duration(seconds: 1)).toIso8601String(),
      },
    );

    final markers = await db.select(db.localSealMarkers).get();
    final seal = await (db.select(db.localSeals)
          ..where((s) => s.id.equals('seal-1')))
        .getSingle();

    expect(changed, isTrue);
    expect(markers, isEmpty);
    expect(seal.markerPlacementPending, isTrue);
  });
}
