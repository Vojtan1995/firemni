import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware, requireRole } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { notFound } from '../lib/errors.js';
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

export default router;
