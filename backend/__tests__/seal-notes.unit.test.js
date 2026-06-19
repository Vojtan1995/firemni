import { describe, expect, it } from '@jest/globals';
import { UserRole } from '@prisma/client';
import {
  applySealNotePatchByRole,
  resolveSealNotesForCreate,
  filterSealNotesForViewer,
} from '../dist/lib/seal-notes.js';

describe('seal-notes RBAC', () => {
  it('worker create sets only internalNote', () => {
    const result = resolveSealNotesForCreate(UserRole.worker, {
      note: 'public',
      internalNote: 'internal',
    });
    expect(result).toEqual({ note: null, internalNote: 'internal' });
  });

  it('vedeni create sets both notes', () => {
    const result = resolveSealNotesForCreate(UserRole.vedeni, {
      note: 'public',
      internalNote: 'internal',
    });
    expect(result).toEqual({ note: 'public', internalNote: 'internal' });
  });

  it('worker update ignores note patch', () => {
    const result = applySealNotePatchByRole(
      UserRole.worker,
      { note: 'existing public', internalNote: 'old' },
      { note: 'hacked', internalNote: 'new internal' },
    );
    expect(result.note).toBe('existing public');
    expect(result.internalNote).toBe('new internal');
  });

  it('vedeni update sets both note and internalNote', () => {
    const result = applySealNotePatchByRole(
      UserRole.vedeni,
      { note: 'old', internalNote: 'old internal' },
      { note: 'new public', internalNote: 'new internal' },
    );
    expect(result.note).toBe('new public');
    expect(result.internalNote).toBe('new internal');
  });

  it('worker viewer strips public note but keeps internal', () => {
    const filtered = filterSealNotesForViewer(UserRole.worker, {
      note: 'secret',
      internalNote: 'internal',
    });
    expect(filtered.note).toBeNull();
    expect(filtered.internalNote).toBe('internal');
  });
});
