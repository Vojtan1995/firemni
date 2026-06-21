import 'package:drift/drift.dart';

import '../../database/database.dart';

/// Navrhne NEJMENŠÍ volné číslo ucpávky v rámci patra (jen návrh – offline můžou
/// dva uživatelé dostat stejné číslo, unikátnost vynucuje backend při uložení).
///
/// Do výpočtu vstupují jen čistě číselná čísla; nečíselná se ignorují. Bez čísel
/// → "1", jinak od nejnižšího existujícího hledá první volné. Stejná logika jako
/// backend `suggestNextSealNumber`.
Future<String> suggestNextSealNumber(
  AppDatabase db, {
  required String floorId,
}) async {
  final rows = await (db.select(db.localSeals)
        ..where((s) => s.floorId.equals(floorId) & s.deletedAt.isNull()))
      .get();
  final used = <int>{};
  final numeric = RegExp(r'^\d+$');
  for (final row in rows) {
    if (numeric.hasMatch(row.sealNumber)) {
      used.add(int.parse(row.sealNumber));
    }
  }
  if (used.isEmpty) return '1';
  var candidate = used.reduce((a, b) => a < b ? a : b);
  while (used.contains(candidate)) {
    candidate += 1;
  }
  return '$candidate';
}
