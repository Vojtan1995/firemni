import 'seal_form_loader.dart';

/// Plocha z rozměrů v mm → m²
double areaFromMm(int lengthMm, int widthMm) =>
    (lengthMm * widthMm) / 1000000.0;

/// VZT: běžné metry
double vztLinearMeters(int lengthMm, int widthMm) =>
    ((2 * lengthMm + 2 * widthMm) * 2) / 1000.0;

/// Plocha prvku s +50 mm na každou stranu
double elementAreaWithMargin(int lengthMm, int widthMm) =>
    ((lengthMm + 50) * (widthMm + 50)) / 1000000.0;

class SealCalculationResult {
  const SealCalculationResult({
    this.openingAreaM2,
    this.deductionAreaM2,
    this.netAreaM2,
    this.linearMeters,
    required this.billableQuantity,
    required this.unit,
    this.netAreaWasNegative = false,
  });

  final double? openingAreaM2;
  final double? deductionAreaM2;
  final double? netAreaM2;
  final double? linearMeters;
  final double billableQuantity;
  final String unit;
  final bool netAreaWasNegative;
}

int? parseMmText(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final n = int.tryParse(text.trim());
  if (n == null || n <= 0) return null;
  return n;
}

SealCalculationResult computeSealEntryPreview({
  required String entryType,
  required int quantityKus,
  int? openingLengthMm,
  int? openingWidthMm,
  int? itemLengthMm,
  int? itemWidthMm,
  required List<SealEntryDraftData> allEntries,
  required int entryIndex,
}) {
  if (entryType == 'VZT' && itemLengthMm != null && itemWidthMm != null) {
    final mb = vztLinearMeters(itemLengthMm, itemWidthMm);
    return SealCalculationResult(
      linearMeters: mb,
      billableQuantity: mb,
      unit: 'mb',
    );
  }

  if (entryType == 'PROSTUP') {
    double? gross;
    if (itemLengthMm != null && itemWidthMm != null) {
      gross = areaFromMm(itemLengthMm, itemWidthMm);
    } else if (openingLengthMm != null && openingWidthMm != null) {
      gross = areaFromMm(openingLengthMm, openingWidthMm);
    }

    if (gross == null) {
      return SealCalculationResult(
        billableQuantity: quantityKus.toDouble(),
        unit: 'kus',
      );
    }

    final hasOpening =
        openingLengthMm != null && openingWidthMm != null;
    final openingArea = hasOpening
        ? areaFromMm(openingLengthMm, openingWidthMm)
        : gross;

    double deduction = 0;
    for (var i = 0; i < allEntries.length; i++) {
      if (i == entryIndex) continue;
      final other = allEntries[i];
      final oL = parseMmText(other.itemLengthMmText);
      final oW = parseMmText(other.itemWidthMmText);
      if (oL != null && oW != null) {
        deduction += elementAreaWithMargin(oL, oW);
      }
    }

    var net = gross;
    var wasNegative = false;
    if (hasOpening && deduction > 0) {
      final raw = openingArea - deduction;
      if (raw < 0) {
        net = 0;
        wasNegative = true;
      } else {
        net = raw;
      }
    }

    return SealCalculationResult(
      openingAreaM2: hasOpening ? openingArea : gross,
      deductionAreaM2: deduction > 0 ? deduction : null,
      netAreaM2: hasOpening && deduction > 0 ? net : null,
      billableQuantity: net,
      unit: 'm2',
      netAreaWasNegative: wasNegative,
    );
  }

  return SealCalculationResult(
    billableQuantity: quantityKus.toDouble(),
    unit: 'kus',
  );
}

String formatArea(double value) => value.toStringAsFixed(3);
String formatMb(double value) => value.toStringAsFixed(1);

String unitLabel(String unit) {
  switch (unit) {
    case 'm2':
      return 'm²';
    case 'mb':
      return 'mb';
    default:
      return 'ks';
  }
}
