import { SealStatus, UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { logActivity, logChange } from './audit.service.js';

import { VEDENI_ROLES } from '../lib/permissions.js';

export const MANAGEMENT_ROLES = VEDENI_ROLES;

export function canWorkerEdit(status: SealStatus) {
  return status === SealStatus.draft || status === SealStatus.checked;
}

export function statusAfterWorkerEdit(currentStatus: SealStatus, userRole: UserRole): SealStatus {
  if (userRole === UserRole.worker && currentStatus === SealStatus.checked) {
    return SealStatus.draft;
  }
  return currentStatus;
}

export function isSealLocked(status: SealStatus) {
  return status === SealStatus.invoiced;
}

export async function assertSealEditable(sealId: string, userRole: UserRole, userId: string) {
  const seal = await prisma.seal.findFirst({
    where: { id: sealId, deletedAt: null },
    include: { job: true },
  });
  if (!seal) throw notFound('Ucpávka nenalezena');
  if (seal.job.isArchived) throw forbidden('Stavba je archivována');
  if (isSealLocked(seal.status)) throw forbidden('Ucpávka je zamčena (fakturováno)');
  if (userRole === UserRole.worker && !canWorkerEdit(seal.status)) {
    throw forbidden('Worker může editovat pouze rozpracované ucpávky');
  }
  return seal;
}

export async function checkDuplicateSealNumber(
  jobId: string,
  floorId: string,
  sealNumber: string,
  excludeId?: string,
) {
  const existing = await prisma.seal.findFirst({
    where: {
      jobId,
      floorId,
      sealNumber,
      deletedAt: null,
      ...(excludeId ? { id: { not: excludeId } } : {}),
    },
  });
  if (existing) throw conflict('Duplicitní číslo ucpávky na tomto patře');
}

export async function changeSealStatus(
  sealId: string,
  newStatus: SealStatus,
  userId: string,
  userRole: UserRole,
) {
  if (userRole === UserRole.worker) throw forbidden('Worker nemůže měnit status');

  const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
  if (!seal) throw notFound('Ucpávka nenalezena');

  const allowed: Record<SealStatus, SealStatus[]> = {
    [SealStatus.draft]: [SealStatus.checked],
    [SealStatus.checked]: [SealStatus.draft, SealStatus.invoiced],
    [SealStatus.invoiced]: [],
  };

  if (!allowed[seal.status].includes(newStatus)) {
    throw badRequest(`Přechod ${seal.status} -> ${newStatus} není povolen`);
  }

  const updated = await prisma.seal.update({
    where: { id: sealId },
    data: {
      status: newStatus,
      version: { increment: 1 },
      updatedById: userId,
    },
  });

  await logChange(userId, 'seal', sealId, 'status', seal.status, newStatus);
  await logActivity(userId, 'status_change', 'seal', sealId, { from: seal.status, to: newStatus });

  return updated;
}

export async function softDeleteSeal(sealId: string, userId: string, reason?: string) {
  const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
  if (!seal) throw notFound('Ucpávka nenalezena');
  if (isSealLocked(seal.status)) throw forbidden('Fakturovanou ucpávku nelze smazat');

  const updated = await prisma.seal.update({
    where: { id: sealId },
    data: {
      deletedAt: new Date(),
      deletedById: userId,
      deleteReason: reason,
      version: { increment: 1 },
    },
  });

  await logActivity(userId, 'soft_delete', 'seal', sealId);
  return updated;
}

export async function restoreSeal(sealId: string, userId: string) {
  const seal = await prisma.seal.findUnique({ where: { id: sealId } });
  if (!seal || !seal.deletedAt) throw notFound('Smazaná ucpávka nenalezena');

  await checkDuplicateSealNumber(seal.jobId, seal.floorId, seal.sealNumber);

  const updated = await prisma.seal.update({
    where: { id: sealId },
    data: {
      deletedAt: null,
      deletedById: null,
      deleteReason: null,
      version: { increment: 1 },
      updatedById: userId,
    },
  });

  await logActivity(userId, 'restore', 'seal', sealId);
  return updated;
}
