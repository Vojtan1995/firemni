import { describe, it, expect } from '@jest/globals';
import { SealStatus, UserRole } from '@prisma/client';
import {
  canWorkerEdit,
  isSealLocked,
  statusAfterWorkerEdit,
} from '../dist/services/seal.service.js';

describe('seal business rules', () => {
  it('worker can edit draft and checked', () => {
    expect(canWorkerEdit(SealStatus.draft)).toBe(true);
    expect(canWorkerEdit(SealStatus.checked)).toBe(true);
    expect(canWorkerEdit(SealStatus.invoiced)).toBe(false);
  });

  it('invoiced is locked', () => {
    expect(isSealLocked(SealStatus.invoiced)).toBe(true);
    expect(isSealLocked(SealStatus.draft)).toBe(false);
  });

  it('worker edit on checked reverts to draft', () => {
    expect(statusAfterWorkerEdit(SealStatus.checked, UserRole.worker)).toBe(
      SealStatus.draft,
    );
    expect(statusAfterWorkerEdit(SealStatus.draft, UserRole.worker)).toBe(
      SealStatus.draft,
    );
    expect(statusAfterWorkerEdit(SealStatus.checked, UserRole.vedeni)).toBe(
      SealStatus.checked,
    );
  });
});
