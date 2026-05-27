import { Router } from 'express';
import { z } from 'zod';
import { Prisma, SealStatus, UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { conflict, forbidden } from '../lib/errors.js';
import {
  checkDuplicateSealNumber,
  canWorkerEdit,
  isSealLocked,
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

router.post('/push', async (req, res, next) => {
  try {
    const { mutations } = pushSchema.parse(req.body);
    const results: Array<{ mutationId: string; status: string; entityId?: string; conflict?: string }> = [];

    for (const mut of mutations) {
      const existing = await prisma.syncMutation.findUnique({
        where: { mutationId: mut.mutationId },
      });
      if (existing?.processedAt) {
        results.push({ mutationId: mut.mutationId, status: 'already_processed', entityId: (existing.result as { entityId?: string })?.entityId });
        continue;
      }

      try {
        const result = await processMutation(mut, req.user!.id, req.user!.role);
        await prisma.syncMutation.upsert({
          where: { mutationId: mut.mutationId },
          create: {
            mutationId: mut.mutationId,
            deviceId: mut.deviceId,
            userId: req.user!.id,
            entityType: mut.entityType,
            operation: mut.operation,
            payload: mut.payload as Prisma.InputJsonValue,
            result,
            processedAt: new Date(),
          },
          update: { result, processedAt: new Date() },
        });
        results.push({ mutationId: mut.mutationId, status: 'ok', entityId: result.entityId });
      } catch (e) {
        const msg = e instanceof Error ? e.message : 'conflict';
        const code = (e as { code?: string }).code === 'CONFLICT' ? 'conflict' : 'error';
        await prisma.syncMutation.upsert({
          where: { mutationId: mut.mutationId },
          create: {
            mutationId: mut.mutationId,
            deviceId: mut.deviceId,
            userId: req.user!.id,
            entityType: mut.entityType,
            operation: mut.operation,
            payload: mut.payload as Prisma.InputJsonValue,
            result: { error: msg },
            processedAt: new Date(),
          },
          update: { result: { error: msg }, processedAt: new Date() },
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
      const jobId = p.jobId as string;
      const floorId = p.floorId as string;
      const sealNumber = p.sealNumber as string;
      await checkDuplicateSealNumber(jobId, floorId, sealNumber);

      const seal = await prisma.seal.create({
        data: {
          jobId,
          floorId,
          sealNumber,
          system: p.system as string,
          construction: p.construction as string,
          location: p.location as string,
          fireRating: p.fireRating as string,
          note: (p.note as string) || null,
          createdById: userId,
          updatedById: userId,
        },
      });
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
      await prisma.seal.update({
        where: { id: sealId },
        data: {
          sealNumber: (p.sealNumber as string) ?? seal.sealNumber,
          system: (p.system as string) ?? seal.system,
          construction: (p.construction as string) ?? seal.construction,
          location: (p.location as string) ?? seal.location,
          fireRating: (p.fireRating as string) ?? seal.fireRating,
          note: (p.note as string | undefined) ?? seal.note,
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

    res.json({
      serverTime: new Date().toISOString(),
      jobs,
      floors,
      seals,
    });
  } catch (e) {
    next(e);
  }
});

export default router;
