import { Router } from 'express';
import { z } from 'zod';
import { Prisma, SealStatus, UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
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
import { entryCreateData, sealEntrySchema } from '../lib/seal-schemas.js';
import {
  refineSealEntriesDimensions,
  refineSealOpeningDimensions,
} from '../lib/zod-helpers.js';

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
    system: z.string().min(1),
    construction: z.string().min(1),
    location: z.string().min(1),
    fireRating: z.string().min(1),
    note: z.string().nullable().optional(),
    internalNote: z.string().nullable().optional(),
    openingLengthMm: z.number().int().positive().optional(),
    openingWidthMm: z.number().int().positive().optional(),
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

router.post('/push', async (req, res, next) => {
  try {
    const { mutations } = pushSchema.parse(req.body);
    const results: Array<{ mutationId: string; status: string; entityId?: string; conflict?: string }> = [];

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
        results.push({ mutationId: mut.mutationId, status: 'ok', entityId: result.entityId });
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

async function processMutation(
  mut: z.infer<typeof mutationSchema>,
  userId: string,
  userRole: UserRole,
): Promise<{ entityId?: string }> {
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

    const seal = await prisma.$transaction(async (tx) => {
      const created = await tx.seal.create({
        data: {
          ...(createPayload.id ? { id: createPayload.id } : {}),
          jobId: createPayload.jobId,
          floorId: createPayload.floorId,
          sealNumber: createPayload.sealNumber,
          system: createPayload.system,
          construction: createPayload.construction,
          location: createPayload.location,
          fireRating: createPayload.fireRating,
          note: createPayload.note ?? null,
          internalNote: createPayload.internalNote ?? null,
          openingLengthMm: createPayload.openingLengthMm ?? null,
          openingWidthMm: createPayload.openingWidthMm ?? null,
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
    const seal = await assertSealEditable(sealId, userRole, userId);
    if (mut.baseVersion !== undefined && mut.baseVersion !== seal.version) {
      throw conflict('Verze entity se neshoduje');
    }
    if (p.sealNumber && p.sealNumber !== seal.sealNumber) {
      await checkDuplicateSealNumber(seal.jobId, seal.floorId, p.sealNumber as string, seal.id);
    }
    const entries = p.entries as z.infer<typeof sealEntrySchema>[] | undefined;
    const nextStatus = statusAfterWorkerEdit(seal.status, userRole);
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
          sealNumber: (p.sealNumber as string) ?? seal.sealNumber,
          system: (p.system as string) ?? seal.system,
          construction: (p.construction as string) ?? seal.construction,
          location: (p.location as string) ?? seal.location,
          fireRating: (p.fireRating as string) ?? seal.fireRating,
          note: patchPayloadField(p, 'note', seal.note),
          internalNote: patchPayloadField(p, 'internalNote', seal.internalNote),
          openingLengthMm: patchPayloadField(p, 'openingLengthMm', seal.openingLengthMm),
          openingWidthMm: patchPayloadField(p, 'openingWidthMm', seal.openingWidthMm),
          status: nextStatus,
          version: { increment: 1 },
          updatedById: userId,
        },
      });
      if (entries?.length) {
        await priceSealEntries(sealId, userId, tx);
      }
    });
    await touchJobParticipant(seal.jobId, userId, 'worker');
    return { entityId: sealId };
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
      ...(role === UserRole.worker ? { isArchived: false } : {}),
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

    const [jobs, floors, seals, jobCount, floorCount, sealCount] = await Promise.all([
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
      prisma.job.count({ where: jobWhere }),
      prisma.jobFloor.count({ where: floorWhere }),
      prisma.seal.count({ where: sealWhere }),
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
      isArchived: true,
      ...jobScope,
      ...(jobId ? { id: jobId } : {}),
    };

    const [deletedJobs, deletedFloors, deletedSeals, archivedJobs] = await Promise.all([
      prisma.job.findMany({
        where: deletedJobWhere,
        select: { id: true, deletedAt: true, updatedAt: true },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.jobFloor.findMany({
        where: deletedFloorWhere,
        select: { id: true, jobId: true, deletedAt: true, updatedAt: true },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.seal.findMany({
        where: deletedSealWhere,
        select: { id: true, jobId: true, floorId: true, deletedAt: true, updatedAt: true },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
      prisma.job.findMany({
        where: archivedJobWhere,
        select: { id: true, updatedAt: true },
        take: SYNC_PULL_BATCH_LIMIT,
      }),
    ]);

    const hasMore =
      jobCount > SYNC_PULL_BATCH_LIMIT ||
      floorCount > SYNC_PULL_BATCH_LIMIT ||
      sealCount > SYNC_PULL_BATCH_LIMIT;

    res.json({
      serverTime: new Date().toISOString(),
      hasMore,
      jobs,
      floors,
      seals,
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
