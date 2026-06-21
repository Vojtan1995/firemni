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

  it('parses new practical filters', () => {
    expect(
      parseSealFilters('mine,status_draft,status_checked,status_invoiced,attention'),
    ).toEqual(['mine', 'status_draft', 'status_checked', 'status_invoiced', 'attention']);
  });

  it('mine filter scopes by createdById when userId present', () => {
    const where = buildSealFilterWhere(['mine'], UserRole.worker, 'user-1');
    expect(where.AND?.[0]).toEqual({ createdById: 'user-1' });
  });

  it('mine filter is a no-op without userId', () => {
    const where = buildSealFilterWhere(['mine'], UserRole.worker);
    expect(where).toEqual({});
  });

  it('status filters map to seal status', () => {
    expect(buildSealFilterWhere(['status_draft'], UserRole.vedeni).AND?.[0]).toEqual({
      status: 'draft',
    });
    expect(buildSealFilterWhere(['status_checked'], UserRole.vedeni).AND?.[0]).toEqual({
      status: 'checked',
    });
    expect(buildSealFilterWhere(['status_invoiced'], UserRole.vedeni).AND?.[0]).toEqual({
      status: 'invoiced',
    });
  });

  it('attention keeps returned OR missing_data rows (post-query)', () => {
    const ok = { system: 'S', construction: 'C', location: 'L', fireRating: 'EI' };
    const rows = [
      // returned -> kept
      { id: 'r', reviewStatus: 'returned', _count: { photos: 1 }, ...ok,
        entries: [{ entryType: 'EL.V.', dimension: '50', quantity: 1, materials: [{ material: 'X' }] }] },
      // complete + not returned -> dropped
      { id: 'ok', reviewStatus: null, _count: { photos: 1 }, ...ok,
        entries: [{ entryType: 'EL.V.', dimension: '50', quantity: 1, materials: [{ material: 'X' }] }] },
      // missing data (no entries) -> kept
      { id: 'm', reviewStatus: null, _count: { photos: 1 }, ...ok, entries: [] },
    ];
    const out = applyPostSealFilters(rows, ['attention']);
    expect(out.map((r) => r.id).sort()).toEqual(['m', 'r']);
  });
});
