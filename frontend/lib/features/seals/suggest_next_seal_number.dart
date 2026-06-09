import 'package:drift/drift.dart';

import '../../database/database.dart';

/// Navrhne další číslo ucpávky v rámci patra (max lokálních + 1).
Future<String> suggestNextSealNumber(
  AppDatabase db, {
  required String floorId,
}) async {
  final rows = await (db.select(db.localSeals)
        ..where((s) => s.floorId.equals(floorId) & s.deletedAt.isNull()))
      .get();
  var max = 0;
  for (final row in rows) {
    final parsed = int.tryParse(row.sealNumber);
    if (parsed != null && parsed > max) {
      max = parsed;
    }
  }
  return '${max + 1}';
}
