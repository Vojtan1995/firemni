import { Router } from 'express';
import { z } from 'zod';
import { Prisma, SealStatus, UserRole, JobStatus, SealTrade } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { syncPushRateLimiter } from '../middleware/security.middleware.js';
import { prisma } from '../lib/prisma.js';
import { AppError, conflict, forbidden } from '../lib/errors.js';
import { hasPermission, type Permission } from '../lib/permissions.js';
import {
  assertFloorBelongsToJob,
  assertJobWritable,
  assertSealReadable,
  buildParticipantJobFilter,
  getParticipantJobIds,
  assertJobReadable,
} from '../services/authorization.service.js';
import { SYNC_PULL_BATCH_LIMIT, SYNC_PUSH_BATCH_LIMIT } from '../lib/limits.js';
import { checkDuplicateSealNumber,
  assertSealEditable,
  isSealLocked,
  changeSealStatus,
  statusAfterWorkerEdit,
} from '../services/seal.service.js';
import { touchJobParticipant } from '../services/job-participant.service.js';
import { priceSealEntries } from '../services/pricing.service.js';
import { logActivity } from '../services/audit.service.js';
import {
  entryCreateData,
  refineSealPatch,
  sealEntrySchema,
  sealPatchObjectSchema,
} from '../lib/seal-schemas.js';
import {
  applySealNotePatchByRole,
  resolveSealNotesForCreate,
  SEAL_NOTE_MAX_LENGTH,
} from '../lib/seal-notes.js';
import {
  refineSealEntriesDimensions,
  refineSealOpeningDimensions,
} from '../lib/zod-helpers.js';
import { deleteSealMarker, upsertSealMarker } from '../services/floor-drawing.service.js';
import {
  captureSealSnapshot,
  recordSealEditRepair,
} from '../services/repair.service.js';

function patchPayloadField<T>(payload: Record<string, unknown>, key: string, current: T): T {
  if (Object.prototype.hasOwnProperty.call(payload, key)) {
    return payload[key] as T;
  }
  return current;
}

const router = Router();
router.use(authMiddleware);

const mutationSchema = z.object({
  mutationId: z.string().uuid(),
  deviceId: z.string(),
  entityType: z.string(),
  operation: z.enum(['create', 'update', 'delete', 'status']),
  payload: z.record(z.unknown()),
  baseVersion: z.number().int().optional(),
});

const pushSchema = z.object({
  mutations: z.array(mutationSchema).max(SYNC_PUSH_BATCH_LIMIT),
});

const sealCreatePayloadSchema = z
  .object({
    id: z.string().uuid().optional(),
    jobId: z.string().uuid(),
    floorId: z.string().uuid(),
    sealNumber: z.string().regex(/^\d+$/),
    trade: z.nativeEnum(SealTrade).optional(),
    system: z.string().min(1),
    construction: z.string().min(1),
    location: z.string().min(1),
    fireRating: z.string().min(1),
    note: z.string().max(SEAL_NOTE_MAX_LENGTH).nullable().optional(),
    internalNote: z.string().max(SEAL_NOTE_MAX_LENGTH).nullable().optional(),
    openingLengthMm: z.number().int().positive().optional(),
    openingWidthMm: z.number().int().positive().optional(),
    markerPlacementPending: z.boolean().optional(),
    entries: z.array(sealEntrySchema).min(1),
  })
  .superRefine((data, ctx) => {
    refineSealOpeningDimensions(data, ctx);
    refineSealEntriesDimensions(data.entries, ctx);
  });

const SYNC_SEAL_PERMISSIONS: Record<string, Permission> = {
  create: 'seal.create',
  update: 'seal.edit',
  delete: 'seal.delete',
  status: 'seal.status',
};

function assertSyncSealPermission(operation: string, userRole: UserRole) {
  const permission = SYNC_SEAL_PERMISSIONS[operation];
  if (!permission || !hasPermission(userRole, permission)) {
    throw forbidden('Nemáte oprávnění pro tuto sync operaci');
  }
}

router.post('/push', syncPushRateLimiter, async (req, res, next) => {
  try {
    const { mutations } = pushSchema.parse(req.body);
    const results: Array<{ mutationId: string; status: string; entityId?: string; conflict?: string; autoMerged?: boolean }> = [];

    for (const mut of mutations) {
      const existing = await prisma.syncMutation.findUnique({
        where: { mutationId: mut.mutationId },
      });
      if (existing?.processedAt) {
        const stored = existing.result as { status?: string; entityId?: string; error?: string } | null;
        if (stored?.status === 'conflict') {
          results.push({
            mutationId: mut.mutationId,
            status: 'conflict',
            conflict: stored.error ?? 'Konflikt',
          });
        } else {
          results.push({
            mutationId: mut.mutationId,
            status: 'already_processed',
            entityId: stored?.entityId,
          });
        }
        continue;
      }

      try {
        const result = await processMutation(mut, req.user!.id, req.user!.role);
        const storedResult = { status: 'ok', ...result };
        await prisma.syncMutation.upsert({
          where: { mutationId: mut.mutationId },
          create: {
            mutationId: mut.mutationId,
            deviceId: mut.deviceId,
            userId: req.user!.id,
            entityType: mut.entityType,
            operation: mut.operation,
            payload: mut.payload as Prisma.InputJsonValue,
            result: storedResult,
            processedAt: new Date(),
          },
          update: { result: storedResult, processedAt: new Date() },
        });
        results.push({
          mutationId: mut.mutationId,
          status: 'ok',
          entityId: result.entityId,
          ...(result.autoMerged ? { autoMerged: true } : {}),
        });
      } catch (e) {
        const msg = e instanceof Error ? e.message : 'conflict';
        const isBusinessError = e instanceof AppError;
        const code = isBusinessError ? 'conflict' : 'error';
        const storedResult = { status: code, error: msg };
        await prisma.syncMutation.upsert({
          where: { mutationId: mut.mutationId },
          create: {
            mutationId: mut.mutationId,
            deviceId: mut.deviceId,
            userId: req.user!.id,
            entityType: mut.entityType,
            operation: mut.operation,
            payload: mut.payload as Prisma.InputJsonValue,
            result: storedResult,
            processedAt: isBusinessError ? new Date() : null,
          },
          update: {
            result: storedResult,
            ...(isBusinessError ? { processedAt: new Date() } : {}),
          },
        });
        results.push({ mutationId: mut.mutationId, status: code, conflict: msg });
      }
    }

    res.json({ results });
  } catch (e) {
    next(e);
  }
});

const markerPayloadSchema = z.object({
  sealId: z.string().uuid(),
  floorId: z.string().uuid(),
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
});

const markerDeletePayloadSchema = z.object({
  sealId: z.string().uuid(),
});

async function processMutation(
  mut: z.infer<typeof mutationSchema>,
  userId: string,
  userRole: UserRole,
): Promise<{ entityId?: string; autoMerged?: boolean }> {
  if (mut.entityType === 'seal_marker') {
    if (!hasPermission(userRole, 'seal.edit')) {
      throw forbidden('Nemáte oprávnění pro umístění značky');
    }
    if (mut.operation === 'update') {
      const body = markerPayloadSchema.parse(mut.payload);
      const marker = await upsertSealMarker(
        body.floorId,
        body.sealId,
        body.x,
        body.y,
        userId,
        userRole,
      );
      return { entityId: marker.sealId };
    }
    if (mut.operation === 'delete') {
      const body = markerDeletePayloadSchema.parse(mut.payload);
      await deleteSealMarker(body.sealId, userId, userRole);
      return { entityId: body.sealId };
    }
    throw conflict('Neznámá sync operace pro značku');
  }

  if (mut.entityType !== 'seal') {
    throw conflict('Neznámá sync entita');
  }

  assertSyncSealPermission(mut.operation, userRole);

  const p = mut.payload as Record<string, string | number | unknown>;

  if (mut.operation === 'create') {
    const createPayload = sealCreatePayloadSchema.parse(mut.payload);
    await assertJobWritable(createPayload.jobId, userRole, userId);
    await assertFloorBelongsToJob(createPayload.floorId, createPayload.jobId);
    await checkDuplicateSealNumber(
      createPayload.jobId,
      createPayload.floorId,
      createPayload.sealNumber,
    );

    const notes = resolveSealNotesForCreate(userRole, {
      note: createPayload.note,
      internalNote: createPayload.internalNote,
    });

    const seal = await prisma.$transaction(async (tx) => {
      const created = await tx.seal.create({
        data: {
          ...(createPayload.id ? { id: createPayload.id } : {}),
          jobId: createPayload.jobId,
          floorId: createPayload.floorId,
          sealNumber: createPayload.sealNumber,
          trade: createPayload.trade ?? SealTrade.neurceno,
          system: createPayload.system,
          construction: createPayload.construction,
          location: createPayload.location,
          fireRating: createPayload.fireRating,
          note: notes.note,
          internalNote: notes.internalNote,
          openingLengthMm: createPayload.openingLengthMm ?? null,
          openingWidthMm: createPayload.openingWidthMm ?? null,
          markerPlacementPending: createPayload.markerPlacementPending ?? false,
          createdById: userId,
          updatedById: userId,
          entries: {
            create: createPayload.entries.map((entry, i) => entryCreateData(entry, i)),
          },
        },
      });
      await priceSealEntries(created.id, userId, tx);
      return created;
    });

    await touchJobParticipant(createPayload.jobId, userId, 'worker');
    return { entityId: seal.id };
  }

  const sealId = (p.id || p.sealId) as string;
  if (!sealId) throw conflict('Chybí ID ucpávky');

  if (mut.operation === 'update') {
    // Stejná validace jako HTTP PATCH (regex čísla, enum trade, .min(1) na
    // textových polích, entries.min(1)). note/internalNote řeší níže
    // applySealNotePatchByRole, proto je ze schématu vynecháme.
    const patch = sealPatchObjectSchema
      .omit({ note: true, internalNote: true })
      .superRefine(refineSealPatch)
      .parse(mut.payload);
    const editReason =
      typeof p.editReason === 'string' ? p.editReason : undefined;
    // overrideLocked umožní vedení/admin upravit i zamčenou (vyfakturovanou)
    // ucpávku. entriesChanged zde záměrně nevynucujeme, aby se nezměnilo dosavadní
    // chování offline editů (sync historicky worksheet-lock nekontroloval).
    const seal = await assertSealEditable(sealId, userRole, userId, {
      overrideLocked: true,
      overrideReason: editReason,
    });
    // Auto-merge souběžné editace: při konfliktu verzí (baseVersion != aktuální)
    // se mutace nezamítá. S `changedFields` (které pole worker reálně změnil) se
    // aplikují jen tato pole a ostatní se ponechají ze serveru – tím se nezahodí
    // cizí souběžná změna. Pole editované oběma stranami vyhrává příchozí (poslední
    // odeslání). Bez `changedFields` (starší klient) je fallback „client-wins"
    // re-base na aktuální verzi. Duplicitní číslo zůstává tvrdý konflikt (viz níže).
    const rawChanged = Array.isArray(
      (p as Record<string, unknown>).changedFields,
    )
      ? ((p as Record<string, unknown>).changedFields as unknown[]).filter(
          (x): x is string => typeof x === 'string',
        )
      : undefined;
    const versionMismatch =
      mut.baseVersion !== undefined && mut.baseVersion !== seal.version;
    const restrictToChanged = versionMismatch && rawChanged !== undefined;
    const fieldChanged = (f: string) =>
      !restrictToChanged || rawChanged!.includes(f);

    // Snímek stavu před úpravou (dohledatelnost – uloží se jako oprava).
    const beforeSnapshot = await captureSealSnapshot(sealId);
    if (
      fieldChanged('sealNumber') &&
      patch.sealNumber &&
      patch.sealNumber !== seal.sealNumber
    ) {
      await checkDuplicateSealNumber(seal.jobId, seal.floorId, patch.sealNumber, seal.id);
    }
    const entries = fieldChanged('entries') ? patch.entries : undefined;
    const nextStatus = statusAfterWorkerEdit(seal.status, userRole);
    const resolvedNotes = applySealNotePatchByRole(
      userRole,
      { note: seal.note, internalNote: seal.internalNote },
      {
        note:
          fieldChanged('note') &&
          Object.prototype.hasOwnProperty.call(p, 'note')
            ? (p.note as string | null)
            : undefined,
        internalNote:
          fieldChanged('internalNote') &&
          Object.prototype.hasOwnProperty.call(p, 'internalNote')
            ? (p.internalNote as string | null)
            : undefined,
      },
    );
    await prisma.$transaction(async (tx) => {
      if (entries?.length) {
        await tx.sealEntry.updateMany({
          where: { sealId },
          data: { deletedAt: new Date() },
        });
        for (let i = 0; i < entries.length; i++) {
          const e = sealEntrySchema.parse(entries[i]);
          const entry = await tx.sealEntry.create({
            data: {
              sealId,
              entryType: e.entryType,
              dimension: e.dimension,
              quantity: e.quantity,
              insulation: e.insulation,
              itemLengthMm: e.itemLengthMm ?? null,
              itemWidthMm: e.itemWidthMm ?? null,
              steelInsulated: e.steelInsulated ?? null,
              electroInstallationType: e.electroInstallationType ?? null,
              sortOrder: i,
            },
          });
          await tx.sealEntryMaterial.createMany({
            data: e.materials.map((material, j) => ({
              entryId: entry.id,
              material,
              sortOrder: j,
            })),
          });
        }
      }
      await tx.seal.update({
        where: { id: sealId },
        data: {
          sealNumber: fieldChanged('sealNumber')
            ? (patch.sealNumber ?? seal.sealNumber)
            : seal.sealNumber,
          trade: fieldChanged('trade') ? (patch.trade ?? seal.trade) : seal.trade,
          system: fieldChanged('system')
            ? (patch.system ?? seal.system)
            : seal.system,
          construction: fieldChanged('construction')
            ? (patch.construction ?? seal.construction)
            : seal.construction,
          location: fieldChanged('location')
            ? (patch.location ?? seal.location)
            : seal.location,
          fireRating: fieldChanged('fireRating')
            ? (patch.fireRating ?? seal.fireRating)
            : seal.fireRating,
          note: resolvedNotes.note,
          internalNote: resolvedNotes.internalNote,
          openingLengthMm: fieldChanged('openingLengthMm')
            ? patchPayloadField(p, 'openingLengthMm', seal.openingLengthMm)
            : seal.openingLengthMm,
          openingWidthMm: fieldChanged('openingWidthMm')
            ? patchPayloadField(p, 'openingWidthMm', seal.openingWidthMm)
            : seal.openingWidthMm,
          markerPlacementPending: fieldChanged('markerPlacementPending')
            ? patchPayloadField(p, 'markerPlacementPending', seal.markerPlacementPending)
            : seal.markerPlacementPending,
          status: nextStatus,
          version: { increment: 1 },
          updatedById: userId,
        },
      });
      if (entries?.length) {
        await priceSealEntries(sealId, userId, tx);
      }
    });
    if (beforeSnapshot) {
      await recordSealEditRepair(sealId, userId, beforeSnapshot, editReason ?? '');
    }
    if (versionMismatch) {
      // Auditní stopa automatického vyřešení konfliktu verzí.
      await logActivity(userId, 'sync_auto_merge', 'seal', sealId, {
        mode: restrictToChanged ? 'field_merge' : 'client_wins',
        changedFields: rawChanged ?? null,
        baseVersion: mut.baseVersion ?? null,
        serverVersion: seal.version,
      });
    }
    await touchJobParticipant(seal.jobId, userId, 'worker');
    return { entityId: sealId, autoMerged: versionMismatch };
  }

  if (mut.operation === 'delete') {
    const seal = await assertSealReadable(sealId, userRole, userId);
    if (isSealLocked(seal.status)) throw conflict('Ucpávka je zamčena');
    await prisma.seal.update({
      where: { id: sealId },
      data: { deletedAt: new Date(), deletedById: userId, version: { increment: 1 } },
    });
    return { entityId: sealId };
  }

  if (mut.operation === 'status') {
    await assertSealReadable(sealId, userRole, userId);
    const newStatus = p.status as SealStatus | undefined;
    if (!newStatus || !Object.values(SealStatus).includes(newStatus)) {
      throw conflict('Neplatný status ucpávky');
    }
    await changeSealStatus(sealId, newStatus, userId, userRole);
    return { entityId: sealId };
  }

  throw conflict('Neznámá sync operace');
}

router.get('/pull', async (req, res, next) => {
  try {
    const since = req.query.since ? new Date(String(req.query.since)) : new Date(0);
    const jobId = req.query.jobId as string | undefined;
    const role = req.user!.role;
    const userId = req.user!.id;

    if (jobId) {
      await assertJobReadable(jobId, role, userId);
    }

    const participantJobIds = await getParticipantJobIds(userId);
    const jobScope = buildParticipantJobFilter(role, participantJobIds);

    const jobWhere = {
      updatedAt: { gt: since },
      deletedAt: null,
      ...jobScope,
      ...(role === UserRole.worker ? { status: JobStatus.active } : {}),
      ...(jobId ? { id: jobId } : {}),
    };

    const floorWhere = {
      updatedAt: { gt: since },
      deletedAt: null,
      ...(Object.keys(jobScope).length > 0
        ? { jobId: jobScope.id as { in: string[] } }
        : jobId
          ? { jobId }
          : {}),
    };

    const sealWhere: Record<string, unknown> = {
      updatedAt: { gt: since },
      deletedAt: null,
      ...(Object.keys(jobScope).length > 0
        ? { jobId: jobScope.id as { in: string[] } }
        : {}),
    };
    if (jobId) sealWhere.jobId = jobId;

    const drawingWhere = {
      updatedAt: { gt: since },
      floor: {
        deletedAt: null,
        ...(Object.keys(jobScope).length > 0
          ? { jobId: jobScope.id as { in: string[] } }
          : jobId
            ? { jobId }
            : {}),
      },
    };

    const markerWhere = {
      updatedAt: { gt: since },
      seal: {
        deletedAt: null,
        ...(Object.keys(jobScope).length > 0
          ? { jobId: jobScope.id as { in: string[] } }
          : {}),
        ...(jobId ? { jobId } : {}),
      },
    };

    const [
      jobs,
      floors,
      seals,
      floorDrawings,
      sealMarkers,
    ] = await Promise.all([
      prisma.job.findMany({
        where: jobWhere,
        include: { floors: { where: { deletedAt: null } } },
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.jobFloor.findMany({
        where: floorWhere,
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.seal.findMany({
        where: sealWhere,
        include: {
          entries: { where: { deletedAt: null }, include: { materials: true } },
          photos: true,
        },
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.floorDrawing.findMany({
        where: drawingWhere,
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.sealMarker.findMany({
        where: markerWhere,
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
    ]);

    const deletedJobWhere = {
      updatedAt: { gt: since },
      deletedAt: { not: null } as const,
      ...jobScope,
      ...(jobId ? { id: jobId } : {}),
    };
    const deletedFloorWhere = {
      updatedAt: { gt: since },
      deletedAt: { not: null } as const,
      ...(Object.keys(jobScope).length > 0
        ? { jobId: jobScope.id as { in: string[] } }
        : jobId
          ? { jobId }
          : {}),
    };
    const deletedSealWhere = {
      updatedAt: { gt: since },
      deletedAt: { not: null } as const,
      ...(Object.keys(jobScope).length > 0
        ? { jobId: jobScope.id as { in: string[] } }
        : {}),
      ...(jobId ? { jobId } : {}),
    };
    const archivedJobWhere = {
      updatedAt: { gt: since },
      deletedAt: null,
      status: { in: [JobStatus.archived, JobStatus.completed] },
      ...jobScope,
      ...(jobId ? { id: jobId } : {}),
    };

    const [deletedJobs, deletedFloors, deletedSeals, archivedJobs] = await Promise.all([
      prisma.job.findMany({
        where: deletedJobWhere,
        select: { id: true, deletedAt: true, updatedAt: true },
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.jobFloor.findMany({
        where: deletedFloorWhere,
        select: { id: true, jobId: true, deletedAt: true, updatedAt: true },
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.seal.findMany({
        where: deletedSealWhere,
        select: { id: true, jobId: true, floorId: true, deletedAt: true, updatedAt: true },
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.job.findMany({
        where: archivedJobWhere,
        select: { id: true, updatedAt: true, status: true, isArchived: true },
        orderBy: { updatedAt: 'asc' },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
    ]);

    // hasMore = některá kolekce vrátila plnou dávku, takže existují další starší
    // změny. Pokrýt VŠECHNY paginované entity (vč. drawings/markers/deleted/
    // archived) – jinak by se zbytek nedotáhl, pokud "došly" jen jobs/floors/seals.
    const batches = [
      jobs,
      floors,
      seals,
      floorDrawings,
      sealMarkers,
      deletedJobs,
      deletedFloors,
      deletedSeals,
      archivedJobs,
    ];
    const hasMore = batches.some((b) => b.length >= SYNC_PULL_BATCH_LIMIT);

    // Kurzor pro další dávku = nejvyšší updatedAt napříč vrácenými záznamy.
    // Klient ho použije jako `since`, takže navazuje přesně tam, kde tato dávka
    // skončila (filtr je `updatedAt > since`). Prázdná dávka → kurzor beze změny.
    let maxUpdatedAt = since;
    for (const batch of batches) {
      for (const row of batch as Array<{ updatedAt: Date }>) {
        if (row.updatedAt > maxUpdatedAt) maxUpdatedAt = row.updatedAt;
      }
    }

    res.json({
      serverTime: new Date().toISOString(),
      nextSince: maxUpdatedAt.toISOString(),
      hasMore,
      jobs,
      floors,
      seals,
      floorDrawings,
      sealMarkers,
      deleted: {
        jobs: deletedJobs,
        floors: deletedFloors,
        seals: deletedSeals,
      },
      archived: {
        jobs: archivedJobs,
      },
    });
  } catch (e) {
    next(e);
  }
});

export default router;
