import { describe, it, expect } from '@jest/globals';
import { UserRole } from '@prisma/client';
import { hasPermission } from '../dist/lib/permissions.js';

describe('permissions matrix', () => {
  it('worker can create seals but not manage jobs', () => {
    expect(hasPermission(UserRole.worker, 'seal.create')).toBe(true);
    expect(hasPermission(UserRole.worker, 'job.manage')).toBe(false);
    expect(hasPermission(UserRole.worker, 'reports.view')).toBe(false);
  });

  it('ucetni can view reports but not manage users', () => {
    expect(hasPermission(UserRole.ucetni, 'reports.view')).toBe(true);
    expect(hasPermission(UserRole.ucetni, 'reports.export')).toBe(true);
    expect(hasPermission(UserRole.ucetni, 'user.manage')).toBe(false);
    expect(hasPermission(UserRole.ucetni, 'seal.status')).toBe(true);
  });

  it('vedeni can manage jobs and users', () => {
    expect(hasPermission(UserRole.vedeni, 'job.manage')).toBe(true);
    expect(hasPermission(UserRole.vedeni, 'user.manage')).toBe(true);
    expect(hasPermission(UserRole.vedeni, 'admin.trash')).toBe(false);
  });

  it('admin has trash access', () => {
    expect(hasPermission(UserRole.admin, 'admin.trash')).toBe(true);
    expect(hasPermission(UserRole.admin, 'seal.restore')).toBe(true);
  });
});
