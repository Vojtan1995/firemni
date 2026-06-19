import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_calculations.dart';
import 'package:ucpavky/features/seals/seal_form_loader.dart';

void main() {
  test('areaFromMm converts dimensions', () {
    expect(areaFromMm(1000, 800), closeTo(0.8, 0.001));
  });

  test('vztLinearMeters matches formula', () {
    expect(vztLinearMeters(500, 300), closeTo(3.2, 0.001));
  });

  test('circleAreaFromDiameterMm uses πr²', () {
    expect(circleAreaFromDiameterMm(100), closeTo(0.00785398, 0.0001));
  });

  test('net passage area: 2 m² minus 500×500 = 1.75 m² (spec example)', () {
    final entries = [
      SealEntryDraftData(entryType: 'PROSTUP'),
      SealEntryDraftData(
        entryType: 'VZT',
        itemLengthMmText: '500',
        itemWidthMmText: '500',
      ),
    ];
    // opening ~2 m² (1414×1414 ≈ 2.0)
    final result = computeSealEntryPreview(
      entryType: 'PROSTUP',
      quantityKus: 1,
      openingLengthMm: 2000,
      openingWidthMm: 1000,
      allEntries: entries,
      entryIndex: 0,
    );
    // 2.0 − 0.25 = 1.75
    expect(result.billableQuantity, closeTo(1.75, 0.001));
  });

  test('net area is never negative', () {
    final entries = [
      SealEntryDraftData(entryType: 'PROSTUP'),
      SealEntryDraftData(
        entryType: 'VZT',
        itemLengthMmText: '900',
        itemWidthMmText: '900',
      ),
    ];
    final result = computeSealEntryPreview(
      entryType: 'PROSTUP',
      quantityKus: 1,
      openingLengthMm: 100,
      openingWidthMm: 100,
      allEntries: entries,
      entryIndex: 0,
    );
    expect(result.billableQuantity, 0);
    expect(result.netAreaWasNegative, isTrue);
  });

  test('PROSTUP net area with VZT deduction', () {
    final entries = [
      SealEntryDraftData(entryType: 'PROSTUP'),
      SealEntryDraftData(
        entryType: 'VZT',
        itemLengthMmText: '500',
        itemWidthMmText: '300',
      ),
    ];
    final result = computeSealEntryPreview(
      entryType: 'PROSTUP',
      quantityKus: 1,
      openingLengthMm: 1000,
      openingWidthMm: 800,
      allEntries: entries,
      entryIndex: 0,
    );
    expect(result.unit, 'm2');
    // Task 5: exaktní odečet bez +50 mm → 0,80 − 0,15 = 0,65
    expect(result.billableQuantity, closeTo(0.65, 0.001));
  });
}
