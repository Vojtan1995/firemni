import { describe, it, expect } from '@jest/globals';
import {
  parseSealFilters,
  applyPostSealFilters,
  buildSealFilterWhere,
} from '../dist/lib/seal-list-filters.js';
import { UserRole } from '@prisma/client';

describe('seal-list-filters', () => {
  it('parses comma-separated filters', () => {
    expect(parseSealFilters('no_photo,returned')).toEqual(['no_photo', 'returned']);
    expect(parseSealFilters('invalid,no_photo')).toEqual(['no_photo']);
  });

  it('filters one_photo post-query', () => {
    const rows = [
      { id: '1', _count: { photos: 0 }, system: 'S', construction: 'C', location: 'L', fireRating: 'EI' },
      { id: '2', _count: { photos: 1 }, system: 'S', construction: 'C', location: 'L', fireRating: 'EI' },
      { id: '3', _count: { photos: 2 }, system: 'S', construction: 'C', location: 'L', fireRating: 'EI' },
    ];
    const out = applyPostSealFilters(rows, ['one_photo']);
    expect(out.map((r) => r.id)).toEqual(['2']);
  });

  it('builds has_note for worker on internal note only', () => {
    const where = buildSealFilterWhere(['has_note'], UserRole.worker);
    expect(where.AND?.[0]).toEqual({ internalNote: { not: null } });
  });
});
