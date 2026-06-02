import 'package:drift/drift.dart';

import '../../database/database.dart';

const duplicateSealNumberMessage =
    'Duplicitní číslo ucpávky na tomto patře';

/// Whether a sync/API message refers to duplicate seal number (D1 / T12).
bool isDuplicateConflictMessage(String? message) {
  if (message == null) return false;
  return message.toLowerCase().contains('duplicit');
}

/// Active local seal with the same number on the same floor (offline pre-check).
Future<LocalSeal?> findLocalDuplicateSeal(
  AppDatabase db, {
  required String jobId,
  required String floorId,
  required String sealNumber,
  String? excludeSealId,
}) async {
  final rows = await (db.select(db.localSeals)
        ..where((s) =>
            s.jobId.equals(jobId) &
            s.floorId.equals(floorId) &
            s.sealNumber.equals(sealNumber) &
            s.deletedAt.isNull()))
      .get();
  for (final row in rows) {
    if (excludeSealId != null && row.id == excludeSealId) continue;
    return row;
  }
  return null;
}
