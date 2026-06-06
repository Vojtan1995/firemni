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

  test('elementAreaWithMargin adds 50mm', () {
    expect(elementAreaWithMargin(500, 300), closeTo(0.1925, 0.001));
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
    expect(result.billableQuantity, closeTo(0.6075, 0.001));
  });
}
