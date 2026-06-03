import { UserRole } from '@prisma/client';
import { forbidden } from './errors.js';
import { Request, Response, NextFunction } from 'express';

export type Permission =
  | 'seal.create'
  | 'seal.edit'
  | 'seal.status'
  | 'seal.delete'
  | 'seal.restore'
  | 'photo.upload'
  | 'photo.delete'
  | 'job.manage'
  | 'floor.manage'
  | 'user.manage'
  | 'reports.view'
  | 'reports.export'
  | 'logs.view'
  | 'admin.trash';

const PERMISSION_MATRIX: Record<Permission, UserRole[]> = {
  'seal.create': [UserRole.worker, UserRole.vedeni, UserRole.admin],
  'seal.edit': [UserRole.worker, UserRole.vedeni, UserRole.admin],
  'seal.status': [UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'seal.delete': [UserRole.vedeni, UserRole.admin],
  'seal.restore': [UserRole.admin],
  'photo.upload': [UserRole.worker, UserRole.vedeni, UserRole.admin],
  'photo.delete': [UserRole.vedeni, UserRole.admin],
  'job.manage': [UserRole.vedeni, UserRole.admin],
  'floor.manage': [UserRole.vedeni, UserRole.admin],
  'user.manage': [UserRole.vedeni, UserRole.admin],
  'reports.view': [UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'reports.export': [UserRole.vedeni, UserRole.ucetni, UserRole.admin],
  'logs.view': [UserRole.vedeni, UserRole.admin],
  'admin.trash': [UserRole.admin],
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
export const REPORTS_ROLES: UserRole[] = [UserRole.vedeni, UserRole.ucetni, UserRole.admin];
