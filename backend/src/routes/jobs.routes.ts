import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '@prisma/client';
import { authMiddleware, requireRole } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { notFound, badRequest } from '../lib/errors.js';
import { logActivity } from '../services/audit.service.js';
import { MANAGEMENT_ROLES } from '../services/seal.service.js';
import { paramId } from '../lib/params.js';

const router = Router();
router.use(authMiddleware);

const projectNumberSchema = z.string().regex(/^\d{8}$/, 'Číslo stavby musí mít 8 číslic');

router.get('/', requireRole(UserRole.management, UserRole.admin), async (req, res, next) => {
  try {
    const archived = req.query.archived === 'true';
    const jobs = await prisma.job.findMany({
      where: { deletedAt: null, isArchived: archived },
      include: { floors: { where: { deletedAt: null }, orderBy: { sortOrder: 'asc' } } },
      orderBy: { createdAt: 'desc' },
    });
    res.json(jobs);
  } catch (e) {
    next(e);
  }
});

router.get('/by-number/:projectNumber', async (req, res, next) => {
  try {
    const num = projectNumberSchema.parse(req.params.projectNumber);
    const job = await prisma.job.findFirst({
      where: { projectNumber: num, deletedAt: null },
      include: { floors: { where: { deletedAt: null }, orderBy: { sortOrder: 'asc' } } },
    });
    if (!job) throw notFound('Stavba s tímto číslem neexistuje');
    if (job.isArchived && req.user!.role === UserRole.worker) {
      throw notFound('Stavba není aktivní');
    }
    res.json(job);
  } catch (e) {
    next(e);
  }
});

const createJobSchema = z.object({
  projectNumber: projectNumberSchema,
  name: z.string().min(1),
  address: z.string().optional(),
  note: z.string().optional(),
});

router.post('/', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const body = createJobSchema.parse(req.body);
    const existing = await prisma.job.findUnique({ where: { projectNumber: body.projectNumber } });
    if (existing) throw badRequest('Stavba s tímto číslem již existuje');

    const job = await prisma.job.create({
      data: { ...body, createdById: req.user!.id },
    });
    await logActivity(req.user!.id, 'create', 'job', job.id);
    res.status(201).json(job);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/archive', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const job = await prisma.job.update({
      where: { id: paramId(req.params.id) },
      data: { isArchived: true },
    });
    await logActivity(req.user!.id, 'archive', 'job', job.id);
    res.json(job);
  } catch (e) {
    next(e);
  }
});

export default router;
