import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/search/search_service.dart';

void main() {
  test('searchLocal photo filters only count current user photos', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 6, 29);

    await db.into(db.localJobs).insert(
          LocalJobsCompanion.insert(
            id: 'job-1',
            projectNumber: '12345678',
            name: 'Scope job',
            updatedAt: now,
          ),
        );
    await db.into(db.localFloors).insert(
          LocalFloorsCompanion.insert(
            id: 'floor-1',
            jobId: 'job-1',
            name: '1NP',
            updatedAt: now,
          ),
        );
    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: 'seal-1',
            jobId: 'job-1',
            floorId: 'floor-1',
            sealNumber: 'A-1',
            system: 'S',
            construction: 'C',
            location: 'L',
            fireRating: 'EI',
            updatedAt: now,
          ),
        );
    await db.into(db.localPhotos).insert(
          LocalPhotosCompanion.insert(
            id: 'photo-user-b',
            userId: const Value('user-b'),
            sealId: 'seal-1',
            localPath: 'b.webp',
            status: const Value('pending'),
            createdAt: now,
          ),
        );

    final userA = await searchLocal(
      db,
      query: '',
      filters: 'no_photo',
      userId: 'user-a',
      isWorker: false,
    );
    final userB = await searchLocal(
      db,
      query: '',
      filters: 'no_photo',
      userId: 'user-b',
      isWorker: false,
    );

    expect(userA.map((h) => h.id), contains('seal-1'));
    expect(userB.map((h) => h.id), isNot(contains('seal-1')));
  });
}
