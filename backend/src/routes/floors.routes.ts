import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware, requireRole } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { notFound, badRequest, conflict } from '../lib/errors.js';
import { logActivity } from '../services/audit.service.js';
import { MANAGEMENT_ROLES } from '../services/seal.service.js';
import { paramId } from '../lib/params.js';

const router = Router({ mergeParams: true });
router.use(authMiddleware);

router.get('/', async (req, res, next) => {
  try {
    const jobId = paramId((req.params as { jobId: string }).jobId);
    const job = await prisma.job.findFirst({ where: { id: jobId, deletedAt: null } });
    if (!job) throw notFound('Stavba nenalezena');

    const floors = await prisma.jobFloor.findMany({
      where: { jobId, deletedAt: null },
      orderBy: { sortOrder: 'asc' },
    });
    res.json(floors);
  } catch (e) {
    next(e);
  }
});

const createFloorSchema = z.object({
  name: z.string().min(1),
  sortOrder: z.number().int().optional(),
});

router.post('/', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const jobId = paramId((req.params as { jobId: string }).jobId);
    const body = createFloorSchema.parse(req.body);
    const floor = await prisma.jobFloor.create({
      data: { jobId, name: body.name, sortOrder: body.sortOrder ?? 0 },
    });
    await logActivity(req.user!.id, 'create', 'job_floor', floor.id, { jobId });
    res.status(201).json(floor);
  } catch (e) {
    next(e);
  }
});

const updateFloorSchema = z.object({
  name: z.string().min(1).optional(),
  sortOrder: z.number().int().optional(),
});

const deleteReasonSchema = z.object({
  deleteReason: z.string().optional(),
});

async function getActiveFloor(jobId: string, floorId: string) {
  const job = await prisma.job.findFirst({ where: { id: jobId, deletedAt: null } });
  if (!job) throw notFound('Stavba nenalezena');
  const floor = await prisma.jobFloor.findFirst({
    where: { id: floorId, jobId, deletedAt: null },
  });
  if (!floor) throw notFound('Patro nenalezeno');
  return floor;
}

router.patch('/:floorId', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const jobId = paramId((req.params as { jobId: string }).jobId);
    const floorId = paramId(req.params.floorId);
    await getActiveFloor(jobId, floorId);
    const body = updateFloorSchema.parse(req.body);
    if (Object.keys(body).length === 0) throw badRequest('Žádná pole k úpravě');

    const floor = await prisma.jobFloor.update({
      where: { id: floorId },
      data: body,
    });
    await logActivity(req.user!.id, 'update', 'job_floor', floor.id, { jobId });
    res.json(floor);
  } catch (e) {
    next(e);
  }
});

router.delete('/:floorId', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const jobId = paramId((req.params as { jobId: string }).jobId);
    const floorId = paramId(req.params.floorId);
    await getActiveFloor(jobId, floorId);
    const { deleteReason } = deleteReasonSchema.parse(req.body ?? {});

    const activeSeals = await prisma.seal.count({
      where: { floorId, deletedAt: null },
    });
    if (activeSeals > 0) {
      throw conflict('Patro nelze smazat – obsahuje aktivní ucpávky');
    }

    const floor = await prisma.jobFloor.update({
      where: { id: floorId },
      data: {
        deletedAt: new Date(),
        deletedById: req.user!.id,
        deleteReason: deleteReason ?? null,
      },
    });
    await logActivity(req.user!.id, 'soft_delete', 'job_floor', floor.id, { jobId });
    res.json({ ok: true, id: floor.id });
  } catch (e) {
    next(e);
  }
});

export default router;
