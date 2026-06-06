import {
  areaFromMm,
  vztLinearMeters,
  elementAreaWithMargin,
  netOpeningArea,
  computeEntryValues,
} from '../dist/services/seal-calculations.js';

describe('seal-calculations', () => {
  test('areaFromMm converts mm to m2', () => {
    expect(areaFromMm(1000, 800)).toBeCloseTo(0.8, 6);
    expect(areaFromMm(500, 300)).toBeCloseTo(0.15, 6);
  });

  test('vztLinearMeters uses perimeter formula', () => {
    expect(vztLinearMeters(500, 300)).toBeCloseTo(3.2, 6);
  });

  test('elementAreaWithMargin adds 50mm per side', () => {
    expect(elementAreaWithMargin(500, 300)).toBeCloseTo(0.1925, 6);
  });

  test('netOpeningArea never returns negative', () => {
    const result = netOpeningArea(0.1, [0.5]);
    expect(result.netAreaM2).toBe(0);
    expect(result.wasNegative).toBe(true);
  });

  test('net opening area example from spec', () => {
    const opening = areaFromMm(1000, 800);
    const vztDeduction = elementAreaWithMargin(500, 300);
    const { netAreaM2 } = netOpeningArea(opening, [vztDeduction]);
    expect(netAreaM2).toBeCloseTo(0.6075, 4);
  });

  test('computeEntryValues for VZT mb', () => {
    const result = computeEntryValues(
      { entryType: 'VZT', itemLengthMm: 500, itemWidthMm: 300, quantity: 1 },
      { openingLengthMm: null, openingWidthMm: null },
      [],
      0,
    );
    expect(result.unit).toBe('mb');
    expect(result.billableQuantity).toBeCloseTo(3.2, 6);
  });

  test('computeEntryValues for PROSTUP with net area deduction', () => {
    const entries = [
      { entryType: 'PROSTUP', itemLengthMm: null, itemWidthMm: null },
      { entryType: 'VZT', itemLengthMm: 500, itemWidthMm: 300 },
    ];
    const opening = { openingLengthMm: 1000, openingWidthMm: 800 };
    const result = computeEntryValues(
      { entryType: 'PROSTUP', itemLengthMm: null, itemWidthMm: null, quantity: 1 },
      opening,
      entries,
      0,
    );
    expect(result.unit).toBe('m2');
    expect(result.billableQuantity).toBeCloseTo(0.6075, 4);
    expect(result.netAreaWasNegative).toBe(false);
  });
});
