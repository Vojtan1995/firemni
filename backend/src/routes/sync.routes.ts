import { Router } from 'express';
import { z } from 'zod';
import { Prisma, SealStatus, UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { AppError, conflict, forbidden } from '../lib/errors.js';
import { checkDuplicateSealNumber,
  canWorkerEdit,
  isSealLocked,
  changeSealStatus,
  statusAfterWorkerEdit,
} from '../services/seal.service.js';

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
  mutations: z.array(mutationSchema),
});

const sealEntryPayloadSchema = z.object({
  entryType: z.string().min(1),
  dimension: z.string().min(1),
  quantity: z.number().int().positive(),
  insulation: z.string().min(1),
  materials: z.array(z.string().min(1)).min(1),
});

const sealCreatePayloadSchema = z.object({
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
  entries: z.array(sealEntryPayloadSchema).min(1),
});

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
  if (mut.entityType === 'seal') {
    const p = mut.payload as Record<string, string | number | unknown>;

    if (mut.operation === 'create') {
      const createPayload = sealCreatePayloadSchema.parse(mut.payload);
      await checkDuplicateSealNumber(
        createPayload.jobId,
        createPayload.floorId,
        createPayload.sealNumber,
      );

      const seal = await prisma.$transaction((tx) =>
        tx.seal.create({
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
            createdById: userId,
            updatedById: userId,
            entries: {
              create: createPayload.entries.map((entry, i) => ({
                entryType: entry.entryType,
                dimension: entry.dimension,
                quantity: entry.quantity,
                insulation: entry.insulation,
                sortOrder: i,
                materials: {
                  create: entry.materials.map((material, j) => ({
                    material,
                    sortOrder: j,
                  })),
                },
              })),
            },
          },
        }),
      );
      return { entityId: seal.id };
    }

    const sealId = (p.id || p.sealId) as string;
    const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null }, include: { job: true } });
    if (!seal) throw conflict('Ucpávka nenalezena');
    if (seal.job.isArchived) throw conflict('Stavba archivována');
    if (isSealLocked(seal.status)) throw conflict('Ucpávka je zamčena');
    if (userRole === UserRole.worker && !canWorkerEdit(seal.status)) {
      throw conflict('Worker nemůže editovat tuto ucpávku');
    }
    if (mut.baseVersion !== undefined && mut.baseVersion !== seal.version) {
      throw conflict('Verze entity se neshoduje');
    }

    if (mut.operation === 'update') {
      if (p.sealNumber && p.sealNumber !== seal.sealNumber) {
        await checkDuplicateSealNumber(seal.jobId, seal.floorId, p.sealNumber as string, seal.id);
      }
      const entries = p.entries as z.infer<typeof sealEntryPayloadSchema>[] | undefined;
      if (entries?.length) {
        await prisma.$transaction(async (tx) => {
          await tx.sealEntry.updateMany({
            where: { sealId },
            data: { deletedAt: new Date() },
          });
          for (let i = 0; i < entries.length; i++) {
            const e = sealEntryPayloadSchema.parse(entries[i]);
            const entry = await tx.sealEntry.create({
              data: {
                sealId,
                entryType: e.entryType,
                dimension: e.dimension,
                quantity: e.quantity,
                insulation: e.insulation,
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
        });
      }
      const nextStatus = statusAfterWorkerEdit(seal.status, userRole);
      await prisma.seal.update({
        where: { id: sealId },
        data: {
          sealNumber: (p.sealNumber as string) ?? seal.sealNumber,
          system: (p.system as string) ?? seal.system,
          construction: (p.construction as string) ?? seal.construction,
          location: (p.location as string) ?? seal.location,
          fireRating: (p.fireRating as string) ?? seal.fireRating,
          note: (p.note as string | undefined) ?? seal.note,
          internalNote: (p.internalNote as string | undefined) ?? seal.internalNote,
          status: nextStatus,
          version: { increment: 1 },
          updatedById: userId,
        },
      });
      return { entityId: sealId };
    }

    if (mut.operation === 'delete') {
      if (userRole === UserRole.worker) throw forbidden();
      await prisma.seal.update({
        where: { id: sealId },
        data: { deletedAt: new Date(), deletedById: userId, version: { increment: 1 } },
      });
      return { entityId: sealId };
    }

    if (mut.operation === 'status') {
      const newStatus = p.status as SealStatus | undefined;
      if (!newStatus || !Object.values(SealStatus).includes(newStatus)) {
        throw conflict('Neplatný status ucpávky');
      }
      await changeSealStatus(sealId, newStatus, userId, userRole);
      return { entityId: sealId };
    }
  }

  return {};
}

router.get('/pull', async (req, res, next) => {
  try {
    const since = req.query.since ? new Date(String(req.query.since)) : new Date(0);
    const jobId = req.query.jobId as string | undefined;

    const sealWhere: Record<string, unknown> = {
      updatedAt: { gt: since },
      deletedAt: null,
    };
    if (jobId) sealWhere.jobId = jobId;

    const [jobs, floors, seals] = await Promise.all([
      prisma.job.findMany({
        where: { updatedAt: { gt: since }, deletedAt: null, ...(req.user!.role === UserRole.worker ? { isArchived: false } : {}) },
        include: { floors: { where: { deletedAt: null } } },
      }),
      prisma.jobFloor.findMany({
        where: { updatedAt: { gt: since }, deletedAt: null },
      }),
      prisma.seal.findMany({
        where: sealWhere,
        include: {
          entries: { where: { deletedAt: null }, include: { materials: true } },
          photos: true,
        },
      }),
    ]);

    const [deletedJobs, deletedFloors, deletedSeals, archivedJobs] = await Promise.all([
      prisma.job.findMany({
        where: { updatedAt: { gt: since }, deletedAt: { not: null } },
        select: { id: true, deletedAt: true, updatedAt: true },
      }),
      prisma.jobFloor.findMany({
        where: { updatedAt: { gt: since }, deletedAt: { not: null } },
        select: { id: true, jobId: true, deletedAt: true, updatedAt: true },
      }),
      prisma.seal.findMany({
        where: { updatedAt: { gt: since }, deletedAt: { not: null }, ...(jobId ? { jobId } : {}) },
        select: { id: true, jobId: true, floorId: true, deletedAt: true, updatedAt: true },
      }),
      prisma.job.findMany({
        where: { updatedAt: { gt: since }, deletedAt: null, isArchived: true },
        select: { id: true, updatedAt: true },
      }),
    ]);

    res.json({
      serverTime: new Date().toISOString(),
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
