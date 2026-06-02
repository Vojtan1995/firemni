import 'seal_constants.dart';

/// Maps API/local seal JSON to entry drafts for edit form (T11).
List<SealEntryDraftData> entryDraftsFromSealMap(Map<String, dynamic> seal) {
  final list = <SealEntryDraftData>[];
  for (final e in (seal['entries'] as List? ?? [])) {
    final m = e as Map<String, dynamic>;
    final materials = <String>[];
    for (final mat in (m['materials'] as List? ?? [])) {
      if (mat is Map) {
        final name = mat['material'] as String?;
        if (name != null && name.isNotEmpty) materials.add(name);
      } else {
        materials.add(mat.toString());
      }
    }
    list.add(SealEntryDraftData(
      entryType: m['entryType'] as String? ?? 'EL.V.',
      dimension: m['dimension'] as String? ?? '',
      quantity: m['quantity'] as int? ?? 1,
      insulation: m['insulation'] as String? ?? 'žádná',
      materials: materials,
    ));
  }
  if (list.isEmpty) {
    return [SealEntryDraftData()];
  }
  return list;
}

/// Mutable entry fields shared by form and loader.
class SealEntryDraftData {
  SealEntryDraftData({
    this.entryType = 'EL.V.',
    String? dimension,
    this.quantity = 1,
    this.insulation = 'žádná',
    List<String>? materials,
  })  : dimension = dimension ?? defaultDimensionForEntry('EL.V.', 'žádná'),
        materials = materials ?? [];

  String entryType;
  String dimension;
  int quantity;
  String insulation;
  List<String> materials;
}
