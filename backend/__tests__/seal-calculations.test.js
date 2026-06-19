import {
  areaFromMm,
  circleAreaFromDiameterMm,
  vztLinearMeters,
  deductionArea,
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

  test('circle area from diameter', () => {
    // Ø100 mm => π*0.05^2 = 0.0078539...
    expect(circleAreaFromDiameterMm(100)).toBeCloseTo(0.0078539816, 8);
  });

  test('deductionArea by shape (Task 5 formulas)', () => {
    expect(deductionArea({ kind: 'rect', widthMm: 500, heightMm: 500 })).toBeCloseTo(0.25, 6);
    expect(deductionArea({ kind: 'circle', diameterMm: 200 })).toBeCloseTo(0.0314159265, 8);
    expect(deductionArea({ kind: 'manual', areaM2: 0.42 })).toBeCloseTo(0.42, 6);
  });

  test('net passage area: 2 m² minus 500×500 = 1.75 m² (spec example)', () => {
    const opening = 2.0;
    const deduction = deductionArea({ kind: 'rect', widthMm: 500, heightMm: 500 });
    const { netAreaM2, wasNegative } = netOpeningArea(opening, [deduction]);
    expect(netAreaM2).toBeCloseTo(1.75, 6);
    expect(wasNegative).toBe(false);
  });

  test('netOpeningArea never returns negative and flags over-deduction', () => {
    const result = netOpeningArea(0.1, [0.5]);
    expect(result.netAreaM2).toBe(0);
    expect(result.wasNegative).toBe(true);
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

  test('computeEntryValues PROSTUP net area = opening minus exact element area', () => {
    // opening 1000×800 = 0.8 m², minus a 500×300 element = 0.15 m² => 0.65 m²
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
    expect(result.billableQuantity).toBeCloseTo(0.65, 4);
    expect(result.netAreaWasNegative).toBe(false);
  });
});
