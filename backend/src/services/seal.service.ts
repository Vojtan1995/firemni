import { Prisma, SealStatus, UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { AppError, badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { logActivity, logChange } from './audit.service.js';
import { assertSealEntriesPriced } from './pricing.service.js';
import { assertSealReadyForChecked } from './seal-validation.service.js';

import { VEDENI_ROLES } from '../lib/permissions.js';
import { hasPermission } from '../lib/permissions.js';
import { jobAccessDeniedMessage, jobAllowsWrites } from '../lib/job-status.js';
import {
  assertFloorReadable,
  assertJobWritable,
  assertSealReadable,
} from './authorization.service.js';
import { csvWithBom } from '../lib/csv-export.js';
import { createNotification } from './notification.service.js';
import { anonymizeUserForViewer } from '../lib/user-privacy.js';
import { isSealLockedByWorksheet, STATUS_LABELS as WORKSHEET_STATUS_LABELS } from './worksheet.service.js';
import { sealTradeLabel } from '../lib/seal-trade.js';

export type BulkItemError = { id: string; message: string };

function bulkErrorMessage(e: unknown): string {
  if (e instanceof AppError) return e.message;
  if (e instanceof Error) return e.message;
  return 'Chyba';
}

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

export async function assertSealEditable(
  sealId: string,
  userRole: UserRole,
  userId: string,
  opts?: { overrideLocked?: boolean; overrideReason?: string; entriesChanged?: boolean },
) {
  const seal = await assertSealReadable(sealId, userRole, userId);
  if (!jobAllowsWrites(seal.job.status)) {
    throw forbidden(jobAccessDeniedMessage(seal.job.status));
  }
  if (isSealLocked(seal.status)) {
    if (
      opts?.overrideLocked &&
      hasPermission(userRole, 'seal.override_locked') &&
      opts.overrideReason?.trim()
    ) {
      await logActivity(userId, 'override_locked_edit', 'seal', sealId, {
        reason: opts.overrideReason.trim(),
      });
      return seal;
    }
    throw forbidden('Ucpávka je zamčena (fakturováno)');
  }
  // Pokud request mění prostupy (entries), zkontroluj, zda nejsou součástí odevzdaného
  // soupisu – ten by se po přepisu entries odpojil od aktuálních dat.
  if (opts?.entriesChanged) {
    const lock = await isSealLockedByWorksheet(sealId);
    if (lock) {
      if (
        opts.overrideLocked &&
        hasPermission(userRole, 'seal.override_locked') &&
        opts.overrideReason?.trim()
      ) {
        await logActivity(userId, 'override_locked_edit', 'seal', sealId, {
          reason: opts.overrideReason.trim(),
          worksheetId: lock.worksheetId,
        });
      } else {
        throw forbidden(
          `Ucpávka je součástí odevzdaného soupisu (${WORKSHEET_STATUS_LABELS[lock.status]}) a nelze upravit prostupy. ` +
            'Vraťte soupis do rozpracovaného stavu nebo kontaktujte vedení.',
        );
      }
    }
  }
  if (userRole === UserRole.worker && !canWorkerEdit(seal.status)) {
    throw forbidden('Worker může editovat pouze rozpracované ucpávky');
  }
  return seal;
}

/**
 * Navrhne NEJMENŠÍ volné číslo v pořadí v rámci patra (jen návrh – unikátnost
 * při uložení vynucuje checkDuplicateSealNumber + partiální unique index).
 *
 * Pravidla: do výpočtu vstupují jen čistě číselná čísla (`^\d+$`), nečíselná
 * (A1, 1A, ...) se ignorují. Bez čísel → "1". Jinak od nejnižšího existujícího
 * čísla hledá první nepoužitou hodnotu. Příklady: {1,2,3}→4, {1,3,4}→2,
 * {5,55}→6, {10,11,13}→12. Vrací běžné číslo bez vodicích nul.
 */
export async function suggestNextSealNumber(floorId: string) {
  const seals = await prisma.seal.findMany({
    where: { floorId, deletedAt: null },
    select: { sealNumber: true },
  });
  const used = new Set<number>();
  for (const seal of seals) {
    if (/^\d+$/.test(seal.sealNumber)) {
      used.add(Number.parseInt(seal.sealNumber, 10));
    }
  }
  if (used.size === 0) return '1';
  let candidate = Math.min(...used);
  while (used.has(candidate)) candidate += 1;
  return String(candidate);
}

/**
 * Převede Prisma P2002 (porušení partiálního unique indexu na čísle ucpávky)
 * na čistý conflict. Backstop proti race condition, kdy dva požadavky projdou
 * `checkDuplicateSealNumber` současně. Ostatní chyby propustí dál.
 */
export function rethrowAsDuplicateSealNumber(e: unknown): never {
  if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
    throw conflict('Duplicitní číslo ucpávky na tomto patře');
  }
  throw e;
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
  comment?: string,
) {
  if (userRole === UserRole.worker) throw forbidden('Worker nemůže měnit status');

  const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
  if (!seal) throw notFound('Ucpávka nenalezena');
  await assertJobWritable(seal.jobId, userRole, userId);

  const allowed: Record<SealStatus, SealStatus[]> = {
    [SealStatus.draft]: [SealStatus.checked],
    [SealStatus.checked]: [SealStatus.draft, SealStatus.invoiced],
    [SealStatus.invoiced]: [],
  };

  if (!allowed[seal.status].includes(newStatus)) {
    throw badRequest(`Přechod ${seal.status} -> ${newStatus} není povolen`);
  }

  if (newStatus === SealStatus.draft && seal.status === SealStatus.checked && !comment?.trim()) {
    throw badRequest('Při vrácení k opravě je povinný komentář');
  }

  if (newStatus === SealStatus.invoiced) {
    const priced = await assertSealEntriesPriced(sealId);
    if (!priced) throw badRequest('Ucpávka obsahuje neoceněné prostupy – nelze fakturovat');
  }

  if (newStatus === SealStatus.checked) {
    await assertSealReadyForChecked(sealId);
  }

  const updated = await prisma.seal.update({
    where: { id: sealId },
    data: {
      status: newStatus,
      version: { increment: 1 },
      updatedById: userId,
    },
  });

  const metadata = comment?.trim() ? { comment: comment.trim() } : undefined;
  await logChange(userId, 'seal', sealId, 'status', seal.status, newStatus, metadata);
  await logActivity(userId, 'status_change', 'seal', sealId, {
    from: seal.status,
    to: newStatus,
    ...(metadata ?? {}),
  });

  return updated;
}

export async function bulkChangeSealStatus(
  sealIds: string[],
  newStatus: SealStatus,
  userId: string,
  userRole: UserRole,
  comment?: string,
) {
  const succeeded = [];
  const failed: BulkItemError[] = [];
  for (const sealId of sealIds) {
    try {
      const updated = await changeSealStatus(sealId, newStatus, userId, userRole, comment);
      succeeded.push(updated);
    } catch (e) {
      failed.push({ id: sealId, message: bulkErrorMessage(e) });
    }
  }
  return { succeeded, failed };
}

export async function bulkMoveSeals(
  sealIds: string[],
  targetFloorId: string,
  userId: string,
  userRole: UserRole,
) {
  const targetFloor = await assertFloorReadable(targetFloorId, userRole, userId);
  const succeeded = [];
  const failed: BulkItemError[] = [];

  for (const sealId of sealIds) {
    try {
      const seal = await assertSealReadable(sealId, userRole, userId);
      if (seal.jobId !== targetFloor.jobId) {
        throw badRequest('Cílové patro musí být ve stejné zakázce');
      }
      await assertJobWritable(seal.jobId, userRole, userId);
      await assertSealEditable(sealId, userRole, userId);
      if (seal.floorId === targetFloorId) {
        throw badRequest('Ucpávka je již na tomto patře');
      }
      await checkDuplicateSealNumber(
        seal.jobId,
        targetFloorId,
        seal.sealNumber,
        sealId,
      );

      const updated = await prisma.seal
        .update({
          where: { id: sealId },
          data: {
            floorId: targetFloorId,
            version: { increment: 1 },
            updatedById: userId,
          },
        })
        .catch(rethrowAsDuplicateSealNumber);

      await prisma.sealMarker.updateMany({
        where: { sealId },
        data: { floorId: targetFloorId },
      });

      await logChange(userId, 'seal', sealId, 'floorId', seal.floorId, targetFloorId);
      await logActivity(userId, 'bulk_move', 'seal', sealId, {
        fromFloorId: seal.floorId,
        toFloorId: targetFloorId,
      });
      succeeded.push(updated);
    } catch (e) {
      failed.push({ id: sealId, message: bulkErrorMessage(e) });
    }
  }

  return { succeeded, failed, targetFloorName: targetFloor.name };
}

export async function buildBulkSealsCsv(
  sealIds: string[],
  userId: string,
  viewerRole: UserRole,
) {
  const rows: string[] = [];
  const header =
    'Stavba;Název stavby;Patro;Číslo ucpávky;Řemeslo;Stav;Systém;Pracovník;Poznámka';

  for (const sealId of sealIds) {
    try {
      const seal = await assertSealReadable(sealId, viewerRole, userId);
      const full = await prisma.seal.findFirst({
        where: { id: seal.id, deletedAt: null },
        include: {
          job: { select: { projectNumber: true, name: true } },
          floor: { select: { name: true } },
          createdBy: { select: { id: true, displayName: true, role: true } },
        },
      });
      if (!full) continue;
      const worker = anonymizeUserForViewer(
        {
          id: full.createdBy.id,
          displayName: full.createdBy.displayName,
          role: full.createdBy.role,
        },
        viewerRole,
      ).displayName;
      const cells = [
        full.job.projectNumber,
        full.job.name,
        full.floor.name,
        full.sealNumber,
        sealTradeLabel(full.trade),
        full.status,
        full.system,
        worker,
        full.note ?? '',
      ].map((v) => `"${String(v).replace(/"/g, '""')}"`);
      rows.push(cells.join(';'));
    } catch {
      // skip inaccessible
    }
  }

  return csvWithBom([header, ...rows].join('\n'));
}

export async function softDeleteSeal(
  sealId: string,
  userId: string,
  userRole: UserRole,
  reason?: string,
) {
  const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
  if (!seal) throw notFound('Ucpávka nenalezena');
  await assertJobWritable(seal.jobId, userRole, userId);
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

export async function restoreSeal(sealId: string, userId: string, userRole: UserRole) {
  const seal = await prisma.seal.findUnique({ where: { id: sealId } });
  if (!seal || !seal.deletedAt) throw notFound('Smazaná ucpávka nenalezena');
  await assertJobWritable(seal.jobId, userRole, userId);

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

export async function reviewSeal(
  sealId: string,
  action: 'approved' | 'returned',
  userId: string,
  userRole: UserRole,
  comment?: string,
) {
  if (userRole !== UserRole.vedeni && userRole !== UserRole.admin) {
    throw forbidden('Revizi může provést pouze vedení');
  }
  if (action === 'returned' && !comment?.trim()) {
    throw badRequest('Při vrácení k opravě je povinný komentář');
  }

  const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
  if (!seal) throw notFound('Ucpávka nenalezena');
  await assertJobWritable(seal.jobId, userRole, userId);

  const reviewStatus = action === 'approved' ? 'approved' : 'returned';
  const data: Record<string, unknown> = {
    reviewStatus,
    reviewComment: action === 'returned' ? comment!.trim() : null,
    version: { increment: 1 },
    updatedById: userId,
  };
  if (action === 'returned') {
    data.status = SealStatus.draft;
  } else if (action === 'approved' && seal.status === SealStatus.draft) {
    await assertSealReadyForChecked(sealId);
    data.status = SealStatus.checked;
  }

  const updated = await prisma.seal.update({ where: { id: sealId }, data });

  await logChange(userId, 'seal', sealId, 'reviewStatus', seal.reviewStatus ?? '', reviewStatus, {
    comment: comment ?? null,
  });
  if (action === 'approved' && seal.status === SealStatus.draft) {
    await logChange(userId, 'seal', sealId, 'status', seal.status, SealStatus.checked);
    await logActivity(userId, 'status_change', 'seal', sealId, {
      from: seal.status,
      to: SealStatus.checked,
      via: 'review_approved',
    });
  }
  if (action === 'returned' && seal.status !== SealStatus.draft) {
    await logChange(userId, 'seal', sealId, 'status', seal.status, SealStatus.draft, {
      comment: comment!.trim(),
    });
    await logActivity(userId, 'status_change', 'seal', sealId, {
      from: seal.status,
      to: SealStatus.draft,
      via: 'review_returned',
    });
  }

  await createNotification({
    userId: seal.createdById,
    type: action === 'approved' ? 'seal_review_approved' : 'seal_review_returned',
    title: action === 'approved' ? 'Ucpávka schválena' : 'Ucpávka vrácena k opravě',
    body:
      action === 'approved'
        ? `Ucpávka #${seal.sealNumber} byla schválena`
        : comment!.trim(),
    entityType: 'seal',
    entityId: sealId,
  });

  return updated;
}
