import { UserRole } from '@prisma/client';
import { forbidden } from './errors.js';
import { Request, Response, NextFunction } from 'express';

export type Permission =
  | 'seal.create'
  | 'seal.edit'
  | 'seal.status'
  | 'seal.delete'
  | 'seal.restore'
  | 'seal.history'
  | 'seal.override_locked'
  | 'photo.upload'
  | 'photo.delete'
  | 'job.manage'
  | 'floor.manage'
  | 'floor.drawing.manage'
  | 'user.manage'
  | 'reports.view'
  | 'reports.export'
  | 'priceList.view'
  | 'priceList.manage'
  | 'logs.view'
  | 'admin.trash'
  | 'admin.backup'
  | 'worksheet.create'
  | 'worksheet.view'
  | 'worksheet.submit'
  | 'worksheet.review'
  | 'worksheet.invoice'
  | 'stats.view';

const PERMISSION_MATRIX: Record<Permission, UserRole[]> = {
  'seal.create': [UserRole.worker, UserRole.vedeni, UserRole.admin],
  'seal.edit': [UserRole.worker, UserRole.vedeni, UserRole.admin],
  'seal.status': [UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'seal.delete': [UserRole.vedeni, UserRole.admin],
  'seal.restore': [UserRole.admin],
  'seal.history': [UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'seal.override_locked': [UserRole.admin],
  'photo.upload': [UserRole.worker, UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'photo.delete': [],
  'job.manage': [UserRole.vedeni, UserRole.admin],
  'floor.manage': [UserRole.vedeni, UserRole.admin],
  'floor.drawing.manage': [UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'user.manage': [UserRole.vedeni, UserRole.admin],
  'reports.view': [UserRole.worker, UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'reports.export': [UserRole.worker, UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'priceList.view': [UserRole.worker, UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'priceList.manage': [UserRole.vedeni, UserRole.admin],
  'logs.view': [UserRole.vedeni, UserRole.admin],
  'admin.trash': [UserRole.admin],
  'admin.backup': [UserRole.admin],
  'worksheet.create': [UserRole.worker, UserRole.ucetni, UserRole.vedeni, UserRole.admin],
  'worksheet.view': [UserRole.worker, UserRole.ucetni, UserRole.vedeni, UserRole.admin],
  'worksheet.submit': [UserRole.worker, UserRole.admin],
  'worksheet.review': [UserRole.vedeni, UserRole.admin],
  'worksheet.invoice': [UserRole.ucetni, UserRole.vedeni, UserRole.admin],
  'stats.view': [UserRole.worker, UserRole.ucetni, UserRole.vedeni, UserRole.admin],
};

export function hasPermission(role: UserRole, permission: Permission): boolean {
  return PERMISSION_MATRIX[permission].includes(role);
}

export function requirePermission(...permissions: Permission[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) return next(forbidden());
    if (permissions.some((p) => hasPermission(req.user!.role, p))) return next();
    return next(forbidden());
  };
}

export const VEDENI_ROLES: UserRole[] = [UserRole.vedeni, UserRole.admin];
export const REPORTS_ROLES: UserRole[] = [
  UserRole.worker,
  UserRole.vedeni,
  UserRole.ucetni,
  UserRole.admin,
];
