import 'seal_form_loader.dart';

/// Plocha z rozměrů v mm → m²
double areaFromMm(int lengthMm, int widthMm) =>
    (lengthMm * widthMm) / 1000000.0;

/// VZT: běžné metry
double vztLinearMeters(int lengthMm, int widthMm) =>
    ((2 * lengthMm + 2 * widthMm) * 2) / 1000.0;

/// Kruh: plocha z průměru v mm → m²
double circleAreaFromDiameterMm(int diameterMm) {
  final r = diameterMm / 2.0;
  return (3.141592653589793 * r * r) / 1000000.0;
}

/// Vytáhne průměr (Ø) z rozměru typu "Ø50" nebo "Ø20-100".
int? diameterFromDimension(String? dim) {
  if (dim == null) return null;
  final n = dim.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  final range = RegExp(r'ø(\d+)-(\d+)').firstMatch(n);
  if (range != null) {
    return ((int.parse(range.group(1)!) + int.parse(range.group(2)!)) / 2).round();
  }
  final single = RegExp(r'ø(\d+)').firstMatch(n);
  if (single != null) return int.parse(single.group(1)!);
  return null;
}

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
        // Obdélník: exaktní plocha bez příplatku (Task 5)
        deduction += areaFromMm(oL, oW);
      } else {
        // Kruh: pokud má rozměr průměr Ø
        final d = diameterFromDimension(other.dimension);
        if (d != null && d > 0) {
          deduction += circleAreaFromDiameterMm(d);
        }
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
