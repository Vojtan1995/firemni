import {
  matchesSizeLabel,
  resolvePriceCategory,
} from '../dist/services/pricing.service.js';

describe('pricing.service', () => {
  test('resolvePriceCategory maps entry types', () => {
    expect(resolvePriceCategory('EL.V.', 'žádná', 'Ø20')).toBe('EL. V.');
    expect(resolvePriceCategory('PROSTUP', 'hořlavá', 'Ø50')).toBe('OC HOŘ');
    expect(resolvePriceCategory('PROSTUP', 'nehořlavá', 'Ø110-150')).toBe('OC');
    expect(resolvePriceCategory('PROSTUP', 'nehořlavá', 'Dilatační')).toBe('PROSTUPY');
    expect(resolvePriceCategory('PROSTUP', 'nehořlavá', 'Ø50', 'm2')).toBe('PROSTUPY');
  });

  test('matchesSizeLabel handles diameter presets', () => {
    expect(matchesSizeLabel('≤ Ø 20', 'Ø20', 'kus')).toBe(true);
    expect(matchesSizeLabel('Ø 30', 'Ø30', 'kus')).toBe(true);
    expect(matchesSizeLabel('Ø 110-150', 'Ø110-150', 'kus')).toBe(true);
    expect(matchesSizeLabel('100/100', '100/100', 'kus')).toBe(true);
    expect(matchesSizeLabel('mb', '5 mb', 'mb')).toBe(true);
    expect(matchesSizeLabel('Dilatační', 'Dilatační spára', 'm2')).toBe(true);
  });
});
