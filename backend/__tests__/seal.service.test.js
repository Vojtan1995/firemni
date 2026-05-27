import { describe, it, expect } from '@jest/globals';

describe('seal business rules', () => {
  it('draft is editable by worker', () => {
    const canWorkerEdit = (status) => status === 'draft';
    expect(canWorkerEdit('draft')).toBe(true);
    expect(canWorkerEdit('checked')).toBe(false);
    expect(canWorkerEdit('invoiced')).toBe(false);
  });

  it('invoiced is locked', () => {
    const isLocked = (status) => status === 'invoiced';
    expect(isLocked('invoiced')).toBe(true);
    expect(isLocked('draft')).toBe(false);
  });
});
