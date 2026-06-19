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
      quantity: _quantityFromApi(m['quantity']),
      insulation: m['insulation'] as String? ?? 'žádná',
      materials: materials,
      itemLengthMmText: m['itemLengthMm']?.toString() ?? '',
      itemWidthMmText: m['itemWidthMm']?.toString() ?? '',
      steelInsulated: m['steelInsulated'] as bool?,
      electroInstallationType: m['electroInstallationType'] as String?,
    ));
  }
  if (list.isEmpty) {
    return [SealEntryDraftData()];
  }
  return list;
}

int _quantityFromApi(dynamic value) {
  if (value == null) return 1;
  if (value is int) return value;
  if (value is num) return value.round();
  final parsed = double.tryParse(value.toString());
  if (parsed == null) return 1;
  return parsed.round();
}

/// Mutable entry fields shared by form and loader.
class SealEntryDraftData {
  SealEntryDraftData({
    this.entryType = 'EL.V.',
    String? dimension,
    this.quantity = 1,
    this.insulation = 'žádná',
    List<String>? materials,
    this.itemLengthMmText = '',
    this.itemWidthMmText = '',
    this.steelInsulated,
    this.electroInstallationType,
  })  : dimension = dimension ?? defaultDimensionForEntry('EL.V.', 'žádná'),
        materials = materials ?? [];

  String entryType;
  String dimension;
  int quantity;
  String insulation;
  List<String> materials;
  String itemLengthMmText;
  String itemWidthMmText;

  /// Doizolováno (Ano/Ne) – pouze pro typ OCEL.
  bool? steelInsulated;

  /// Typ elektro instalace (Svazek/Husí krk/Žlab) – pouze pro typ EL.V.
  String? electroInstallationType;
}
