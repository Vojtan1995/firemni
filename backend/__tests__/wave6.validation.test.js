import { describe, it, expect } from '@jest/globals';
import { sealBodySchema, sealEntrySchema } from '../dist/lib/seal-schemas.js';
import { parseIsoDateQuery } from '../dist/lib/zod-helpers.js';
import {
  ADMIN_ANONYMOUS_LABEL,
  anonymizeUserForViewer,
} from '../dist/lib/user-privacy.js';
import { UserRole } from '@prisma/client';

describe('wave 6 validation and privacy', () => {
  const baseSeal = {
    jobId: '00000000-0000-0000-0000-000000000010',
    floorId: '00000000-0000-0000-0000-000000000011',
    sealNumber: '123',
    system: 'S',
    construction: 'Stěna',
    location: 'A',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'EL.V.',
        dimension: 'Ø20',
        quantity: 1,
        insulation: 'žádná',
        materials: ['Pena'],
      },
    ],
  };

  it('rejects empty seal text fields', () => {
    const result = sealBodySchema.safeParse({ ...baseSeal, system: '' });
    expect(result.success).toBe(false);
  });

  it('rejects paired dimensions when only length is set', () => {
    const result = sealEntrySchema.safeParse({
      entryType: 'VZT',
      dimension: '100x200',
      quantity: 1,
      insulation: 'žádná',
      materials: ['Pena'],
      itemLengthMm: 100,
    });
    expect(result.success).toBe(false);
  });

  it('accepts paired dimensions when both are set', () => {
    const result = sealEntrySchema.safeParse({
      entryType: 'VZT',
      dimension: '100x200',
      quantity: 1,
      insulation: 'žádná',
      materials: ['Pena'],
      itemLengthMm: 100,
      itemWidthMm: 200,
    });
    expect(result.success).toBe(true);
  });

  it('parseIsoDateQuery accepts YYYY-MM-DD', () => {
    const date = parseIsoDateQuery('2026-06-01');
    expect(date?.toISOString()).toBe('2026-06-01T00:00:00.000Z');
  });

  it('parseIsoDateQuery rejects invalid format', () => {
    expect(() => parseIsoDateQuery('01.06.2026')).toThrow(/YYYY-MM-DD/);
  });

  it('anonymizes admin for vedeni viewer', () => {
    const user = anonymizeUserForViewer(
      {
        id: 'admin-id',
        username: 'admin',
        displayName: 'Administrátor systému',
        role: UserRole.admin,
      },
      UserRole.vedeni,
    );
    expect(user.displayName).toBe(ADMIN_ANONYMOUS_LABEL);
    expect(user.username).toBe('admin');
  });

  it('keeps admin visible for admin viewer', () => {
    const user = anonymizeUserForViewer(
      {
        id: 'admin-id',
        username: 'admin',
        displayName: 'Administrátor systému',
        role: UserRole.admin,
      },
      UserRole.admin,
    );
    expect(user.displayName).toBe('Administrátor systému');
  });
});
