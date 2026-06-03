import { Router } from 'express';
import { z } from 'zod';
import { SealStatus, UserRole } from '@prisma/client';
import { authMiddleware, requireRole } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { prisma } from '../lib/prisma.js';
import { notFound } from '../lib/errors.js';
import { logActivity, logChange } from '../services/audit.service.js';
import { paramId } from '../lib/params.js';
import {
  assertSealEditable,
  checkDuplicateSealNumber,
  changeSealStatus,
  softDeleteSeal,
  restoreSeal,
  MANAGEMENT_ROLES,
  statusAfterWorkerEdit,
} from '../services/seal.service.js';

const router = Router();
router.use(authMiddleware);

const entrySchema = z.object({
  entryType: z.string(),
  dimension: z.string(),
  quantity: z.number().int().positive(),
  insulation: z.string(),
  materials: z.array(z.string()).min(1),
});

const sealBodySchema = z.object({
  jobId: z.string().uuid(),
  floorId: z.string().uuid(),
  sealNumber: z.string().regex(/^\d+$/, 'Číslo ucpávky musí být číselné'),
  system: z.string(),
  construction: z.string(),
  location: z.string(),
  fireRating: z.string(),
  note: z.string().optional(),
  entries: z.array(entrySchema).min(1),
  baseVersion: z.number().int().optional(),
});

router.get('/trash', requirePermission('admin.trash'), async (_req, res, next) => {
  try {
    const seals = await prisma.seal.findMany({
      where: { deletedAt: { not: null } },
      include: {
        job: { select: { projectNumber: true, name: true } },
        floor: { select: { name: true } },
      },
      orderBy: { deletedAt: 'desc' },
      take: 200,
    });

    const deleterIds = [...new Set(seals.map((s) => s.deletedById).filter((id): id is string => !!id))];
    const deleters =
      deleterIds.length > 0
        ? await prisma.user.findMany({
            where: { id: { in: deleterIds } },
            select: { id: true, displayName: true, username: true },
          })
        : [];
    const deleterMap = new Map(deleters.map((u) => [u.id, u]));

    res.json(
      seals.map((s) => {
        const deleter = s.deletedById ? deleterMap.get(s.deletedById) : undefined;
        return {
          entityType: 'seal',
          id: s.id,
          sealNumber: s.sealNumber,
          status: s.status,
          stavba: s.job.projectNumber,
          nazevStavby: s.job.name,
          patro: s.floor.name,
          deletedAt: s.deletedAt,
          deletedByName: deleter?.displayName ?? deleter?.username ?? null,
          deleteReason: s.deleteReason,
        };
      }),
    );
  } catch (e) {
    next(e);
  }
});

router.get('/floors/:floorId/seals', async (req, res, next) => {
  try {
    const seals = await prisma.seal.findMany({
      where: { floorId: paramId(req.params.floorId), deletedAt: null },
      select: {
        id: true,
        sealNumber: true,
        status: true,
        version: true,
        updatedAt: true,
      },
      orderBy: { sealNumber: 'asc' },
    });
    res.json(seals);
  } catch (e) {
    next(e);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const seal = await prisma.seal.findFirst({
      where: { id: paramId(req.params.id), deletedAt: null },
      include: {
        entries: {
          where: { deletedAt: null },
          include: { materials: { orderBy: { sortOrder: 'asc' } } },
          orderBy: { sortOrder: 'asc' },
        },
        photos: { orderBy: { createdAt: 'asc' } },
      },
    });
    if (!seal) throw notFound('Ucpávka nenalezena');
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.post('/', async (req, res, next) => {
  try {
    const body = sealBodySchema.parse(req.body);
    await checkDuplicateSealNumber(body.jobId, body.floorId, body.sealNumber);

    const seal = await prisma.seal.create({
      data: {
        jobId: body.jobId,
        floorId: body.floorId,
        sealNumber: body.sealNumber,
        system: body.system,
        construction: body.construction,
        location: body.location,
        fireRating: body.fireRating,
        note: body.note,
        status: SealStatus.draft,
        createdById: req.user!.id,
        updatedById: req.user!.id,
        entries: {
          create: body.entries.map((e, i) => ({
            entryType: e.entryType,
            dimension: e.dimension,
            quantity: e.quantity,
            insulation: e.insulation,
            sortOrder: i,
            materials: {
              create: e.materials.map((m, j) => ({ material: m, sortOrder: j })),
            },
          })),
        },
      },
      include: {
        entries: { include: { materials: true } },
        photos: true,
      },
    });

    await logActivity(req.user!.id, 'create', 'seal', seal.id);
    res.status(201).json(seal);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id', async (req, res, next) => {
  try {
    const body = sealBodySchema.partial().extend({
      entries: z.array(entrySchema).optional(),
      baseVersion: z.number().int(),
    }).parse(req.body);

    const existing = await assertSealEditable(paramId(req.params.id), req.user!.role, req.user!.id);

    if (body.baseVersion !== undefined && body.baseVersion !== existing.version) {
      const { conflict: c } = await import('../lib/errors.js');
      throw c('Entita byla mezitím změněna jiným uživatelem');
    }

    if (body.sealNumber && body.sealNumber !== existing.sealNumber) {
      await checkDuplicateSealNumber(
        existing.jobId,
        existing.floorId,
        body.sealNumber,
        existing.id,
      );
    }

    const updateData: Record<string, unknown> = {
      version: { increment: 1 },
      updatedById: req.user!.id,
    };
    const nextStatus = statusAfterWorkerEdit(existing.status, req.user!.role);
    if (nextStatus !== existing.status) {
      updateData.status = nextStatus;
      await logChange(req.user!.id, 'seal', existing.id, 'status', existing.status, nextStatus);
    }
    const fields = ['sealNumber', 'system', 'construction', 'location', 'fireRating', 'note'] as const;
    for (const f of fields) {
      if (body[f] !== undefined) {
        if (String(existing[f]) !== String(body[f])) {
          await logChange(req.user!.id, 'seal', existing.id, f, String(existing[f]), String(body[f]));
        }
        updateData[f] = body[f];
      }
    }

    if (body.entries) {
      await prisma.$transaction(async (tx) => {
        await tx.sealEntry.updateMany({
          where: { sealId: existing.id },
          data: { deletedAt: new Date() },
        });
        for (let i = 0; i < body.entries!.length; i++) {
          const e = body.entries![i];
          const entry = await tx.sealEntry.create({
            data: {
              sealId: existing.id,
              entryType: e.entryType,
              dimension: e.dimension,
              quantity: e.quantity,
              insulation: e.insulation,
              sortOrder: i,
            },
          });
          await tx.sealEntryMaterial.createMany({
            data: e.materials.map((m, j) => ({
              entryId: entry.id,
              material: m,
              sortOrder: j,
            })),
          });
        }
      });
    }

    const seal = await prisma.seal.update({
      where: { id: existing.id },
      data: updateData,
      include: {
        entries: { where: { deletedAt: null }, include: { materials: true } },
        photos: true,
      },
    });

    await logActivity(req.user!.id, 'update', 'seal', seal.id);
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/status', requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const { status } = z.object({ status: z.nativeEnum(SealStatus) }).parse(req.body);
    const seal = await changeSealStatus(paramId(req.params.id), status, req.user!.id, req.user!.role);
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.delete('/:id', async (req, res, next) => {
  try {
    if (req.user!.role === UserRole.worker) {
      await assertSealEditable(paramId(req.params.id), req.user!.role, req.user!.id);
    }
    const reason = typeof req.body?.reason === 'string' ? req.body.reason : undefined;
    const seal = await softDeleteSeal(paramId(req.params.id), req.user!.id, reason);
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/restore', requirePermission('seal.restore'), async (req, res, next) => {
  try {
    const seal = await restoreSeal(paramId(req.params.id), req.user!.id);
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

export default router;
