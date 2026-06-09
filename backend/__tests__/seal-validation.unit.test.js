import { describe, expect, it } from '@jest/globals';
import { validateSealForChecked } from '../dist/services/seal-validation.service.js';

describe('validateSealForChecked', () => {
  const complete = {
    system: 'Hilti',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    photos: [{ id: 'p1' }],
    entries: [
      {
        entryType: 'EL.V.',
        dimension: '20',
        quantity: 1,
        materials: [{ material: 'Pena' }],
      },
    ],
  };

  it('passes complete seal', () => {
    expect(validateSealForChecked(complete)).toEqual([]);
  });

  it('reports missing photo and fields', () => {
    const issues = validateSealForChecked({
      ...complete,
      photos: [],
      system: '',
      entries: [
        {
          entryType: '',
          dimension: '',
          quantity: 0,
          materials: [],
        },
      ],
    });
    expect(issues.some((i) => i.field === 'photos')).toBe(true);
    expect(issues.some((i) => i.field === 'system')).toBe(true);
    expect(issues.some((i) => i.message.includes('typ prostupu'))).toBe(true);
  });
});
