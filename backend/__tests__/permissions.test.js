import { describe, it, expect } from '@jest/globals';
import { UserRole } from '@prisma/client';
import { hasPermission } from '../dist/lib/permissions.js';

describe('permissions matrix', () => {
  it('worker can create seals, view reports and price list but not manage jobs', () => {
    expect(hasPermission(UserRole.worker, 'seal.create')).toBe(true);
    expect(hasPermission(UserRole.worker, 'job.manage')).toBe(false);
    expect(hasPermission(UserRole.worker, 'reports.view')).toBe(true);
    expect(hasPermission(UserRole.worker, 'reports.export')).toBe(true);
    expect(hasPermission(UserRole.worker, 'priceList.view')).toBe(true);
    expect(hasPermission(UserRole.worker, 'stats.view')).toBe(true);
    expect(hasPermission(UserRole.worker, 'worksheet.create')).toBe(true);
    expect(hasPermission(UserRole.worker, 'seal.history')).toBe(false);
  });

  it('ucetni can view reports and invoice worksheets but not manage users or edit seals', () => {
    expect(hasPermission(UserRole.ucetni, 'reports.view')).toBe(true);
    expect(hasPermission(UserRole.ucetni, 'reports.export')).toBe(true);
    expect(hasPermission(UserRole.ucetni, 'user.manage')).toBe(false);
    expect(hasPermission(UserRole.ucetni, 'seal.status')).toBe(true);
    expect(hasPermission(UserRole.ucetni, 'seal.create')).toBe(false);
    expect(hasPermission(UserRole.ucetni, 'seal.edit')).toBe(false);
    expect(hasPermission(UserRole.ucetni, 'worksheet.invoice')).toBe(true);
    expect(hasPermission(UserRole.ucetni, 'worksheet.review')).toBe(false);
    expect(hasPermission(UserRole.ucetni, 'stats.view')).toBe(true);
  });

  it('vedeni can manage jobs and users', () => {
    expect(hasPermission(UserRole.vedeni, 'job.manage')).toBe(true);
    expect(hasPermission(UserRole.vedeni, 'user.manage')).toBe(true);
    expect(hasPermission(UserRole.vedeni, 'admin.trash')).toBe(false);
    expect(hasPermission(UserRole.vedeni, 'seal.history')).toBe(true);
    expect(hasPermission(UserRole.vedeni, 'worksheet.review')).toBe(true);
  });

  it('admin has trash access and full worksheet permissions', () => {
    expect(hasPermission(UserRole.admin, 'admin.trash')).toBe(true);
    expect(hasPermission(UserRole.admin, 'seal.restore')).toBe(true);
    expect(hasPermission(UserRole.admin, 'worksheet.submit')).toBe(true);
    expect(hasPermission(UserRole.admin, 'photo.delete')).toBe(false);
  });
});
