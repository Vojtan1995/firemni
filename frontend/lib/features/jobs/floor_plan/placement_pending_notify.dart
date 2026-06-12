import 'package:drift/drift.dart';

import '../../../database/database.dart';

/// Počet ucpávek čekajících na zakreslení na patře.
Future<int> countPlacementPendingSeals(
  AppDatabase db, {
  required String floorId,
}) async {
  final seals = await (db.select(db.localSeals)
        ..where((s) =>
            s.floorId.equals(floorId) &
            s.deletedAt.isNull() &
            s.markerPlacementPending.equals(true)))
      .get();
  if (seals.isEmpty) return 0;

  final markers = await (db.select(db.localSealMarkers)
        ..where((m) => m.floorId.equals(floorId)))
      .get();
  final placed = markers.map((m) => m.sealId).toSet();
  return seals.where((s) => !placed.contains(s.id)).length;
}

Future<int> countPlacementPendingForJob(
  AppDatabase db, {
  required String jobId,
}) async {
  final floors = await (db.select(db.localFloors)
        ..where((f) => f.jobId.equals(jobId) & f.deletedAt.isNull()))
      .get();
  var total = 0;
  for (final f in floors) {
    total += await countPlacementPendingSeals(db, floorId: f.id);
  }
  return total;
}
