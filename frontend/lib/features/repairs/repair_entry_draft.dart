/// Odlehčený model jednoho prostupu ve formuláři opravy — bez automatických
/// výpočtů ploch/cen (oprava se neoceňuje, viz BACKEND FÁZE 3).
class RepairEntryDraftData {
  RepairEntryDraftData({
    this.entryType = '',
    this.dimension = '',
    this.quantity = 1,
    this.insulation = '',
    List<String>? materials,
    this.itemLengthMmText = '',
    this.itemWidthMmText = '',
    this.steelInsulated,
    this.electroInstallationType,
  }) : materials = materials ?? [];

  String entryType;
  String dimension;
  int quantity;
  String insulation;
  List<String> materials;
  String itemLengthMmText;
  String itemWidthMmText;
  bool? steelInsulated;
  String? electroInstallationType;

  factory RepairEntryDraftData.fromMap(Map<String, dynamic> m) {
    final materialsRaw = m['materials'] as List?;
    return RepairEntryDraftData(
      entryType: m['entryType'] as String? ?? '',
      dimension: m['dimension'] as String? ?? '',
      quantity: ((m['quantity'] as num?) ?? 1).round().clamp(1, 999999),
      insulation: m['insulation'] as String? ?? '',
      materials: materialsRaw == null
          ? <String>[]
          : materialsRaw
              .map((x) => x is Map ? x['material'].toString() : x.toString())
              .toList(),
      itemLengthMmText: m['itemLengthMm']?.toString() ?? '',
      itemWidthMmText: m['itemWidthMm']?.toString() ?? '',
      steelInsulated: m['steelInsulated'] as bool?,
      electroInstallationType: m['electroInstallationType'] as String?,
    );
  }

  Map<String, dynamic> toPayload() {
    final l = int.tryParse(itemLengthMmText.trim());
    final w = int.tryParse(itemWidthMmText.trim());
    return {
      'entryType': entryType,
      'dimension': dimension,
      'quantity': quantity,
      'insulation': insulation,
      'materials': materials,
      if (l != null) 'itemLengthMm': l,
      if (w != null) 'itemWidthMm': w,
      if (entryType == 'OCEL') 'steelInsulated': steelInsulated,
      if (entryType == 'EL.V.')
        'electroInstallationType': electroInstallationType,
    };
  }
}
