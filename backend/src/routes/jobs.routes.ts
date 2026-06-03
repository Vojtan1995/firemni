import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '@prisma/client';
import { authMiddleware, requireRole } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';
import { notFound, badRequest, conflict } from '../lib/errors.js';
import { logActivity } from '../services/audit.service.js';
import { MANAGEMENT_ROLES } from '../services/seal.service.js';
import { paramId } from '../lib/params.js';

const router = Router();
router.use(authMiddleware);

const projectNumberSchema = z.string().regex(/^\d{8}$/, 'Číslo stavby musí mít 8 číslic');

router.get('/', requireRole(UserRole.vedeni, UserRole.admin), async (req, res, next) => {
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

const updateJobSchema = z.object({
  name: z.string().min(1).optional(),
  address: z.string().optional().nullable(),
  note: z.string().optional().nullable(),
});

const deleteReasonSchema = z.object({
  deleteReason: z.string().optional(),
});

async function getActiveJob(id: string) {
  const job = await prisma.job.findFirst({ where: { id, deletedAt: null } });
  if (!job) throw notFound('Stavba nenalezena');
  return job;
}

router.patch('/:id/archive', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    await getActiveJob(id);
    const job = await prisma.job.update({
      where: { id },
      data: { isArchived: true },
    });
    await logActivity(req.user!.id, 'archive', 'job', job.id);
    res.json(job);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/unarchive', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    await getActiveJob(id);
    const job = await prisma.job.update({
      where: { id },
      data: { isArchived: false },
    });
    await logActivity(req.user!.id, 'unarchive', 'job', job.id);
    res.json(job);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    await getActiveJob(id);
    const body = updateJobSchema.parse(req.body);
    if (Object.keys(body).length === 0) throw badRequest('Žádná pole k úpravě');

    const job = await prisma.job.update({
      where: { id },
      data: {
        ...(body.name !== undefined ? { name: body.name } : {}),
        ...(body.address !== undefined ? { address: body.address } : {}),
        ...(body.note !== undefined ? { note: body.note } : {}),
      },
    });
    await logActivity(req.user!.id, 'update', 'job', job.id);
    res.json(job);
  } catch (e) {
    next(e);
  }
});

router.delete('/:id', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    await getActiveJob(id);
    const { deleteReason } = deleteReasonSchema.parse(req.body ?? {});

    const activeSeals = await prisma.seal.count({
      where: { jobId: id, deletedAt: null },
    });
    if (activeSeals > 0) {
      throw conflict('Stavbu nelze smazat – obsahuje aktivní ucpávky');
    }

    const job = await prisma.job.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        deletedById: req.user!.id,
        deleteReason: deleteReason ?? null,
      },
    });
    await logActivity(req.user!.id, 'soft_delete', 'job', job.id);
    res.json({ ok: true, id: job.id });
  } catch (e) {
    next(e);
  }
});

export default router;
