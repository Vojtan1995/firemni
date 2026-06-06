import { Router } from 'express';
import { z } from 'zod';
import { SealStatus, UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { prisma } from '../lib/prisma.js';
import { notFound } from '../lib/errors.js';
import { getSealHistory, logActivity, logChange } from '../services/audit.service.js';
import { touchJobParticipant } from '../services/job-participant.service.js';
import { priceSealEntries } from '../services/pricing.service.js';
import { paramId } from '../lib/params.js';
import {
  assertSealEditable,
  bulkChangeSealStatus,
  changeSealStatus,
  checkDuplicateSealNumber,
  restoreSeal,
  softDeleteSeal,
  statusAfterWorkerEdit,
} from '../services/seal.service.js';
import { entryCreateData, sealBodySchema, sealEntrySchema } from '../lib/seal-schemas.js';

const router = Router();
router.use(authMiddleware);

const showWorkerInList = (role: UserRole) =>
  role === UserRole.ucetni || role === UserRole.vedeni || role === UserRole.admin;

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
    const role = req.user!.role;
    const showWorker = showWorkerInList(role);
    const seals = await prisma.seal.findMany({
      where: { floorId: paramId(req.params.floorId), deletedAt: null },
      select: {
        id: true,
        sealNumber: true,
        system: true,
        fireRating: true,
        status: true,
        version: true,
        updatedAt: true,
        ...(showWorker
            ? { createdBy: { select: { id: true, displayName: true } } }
            : {}),
        entries: {
          where: { deletedAt: null },
          take: 1,
          orderBy: { sortOrder: 'asc' },
          select: { dimension: true },
        },
        _count: { select: { photos: true } },
      },
      orderBy: { sealNumber: 'asc' },
    });

    res.json(
      seals.map((s) => ({
        id: s.id,
        sealNumber: s.sealNumber,
        system: s.system,
        fireRating: s.fireRating,
        dimension: s.entries[0]?.dimension ?? '',
        status: s.status,
        version: s.version,
        updatedAt: s.updatedAt,
        photoCount: s._count.photos,
        worker: showWorker && 'createdBy' in s ? s.createdBy : undefined,
      })),
    );
  } catch (e) {
    next(e);
  }
});

router.post('/bulk-status', requirePermission('seal.status'), async (req, res, next) => {
  try {
    const body = z
      .object({
        ids: z.array(z.string().uuid()).min(1),
        status: z.nativeEnum(SealStatus),
        comment: z.string().optional(),
      })
      .parse(req.body);
    const results = await bulkChangeSealStatus(
      body.ids,
      body.status,
      req.user!.id,
      req.user!.role,
      body.comment,
    );
    res.json({ updated: results.length, seals: results });
  } catch (e) {
    next(e);
  }
});

router.get('/:id/history', requirePermission('seal.history'), async (req, res, next) => {
  try {
    const sealId = paramId(req.params.id);
    const seal = await prisma.seal.findFirst({ where: { id: sealId, deletedAt: null } });
    if (!seal) throw notFound('Ucpávka nenalezena');
    const history = await getSealHistory(sealId);
    res.json(history);
  } catch (e) {
    next(e);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const seal = await prisma.seal.findFirst({
      where: { id: paramId(req.params.id), deletedAt: null },
      include: {
        createdBy: { select: { id: true, displayName: true, username: true } },
        updatedBy: { select: { id: true, displayName: true, username: true } },
        entries: {
          where: { deletedAt: null },
          include: { materials: { orderBy: { sortOrder: 'asc' } } },
          orderBy: { sortOrder: 'asc' },
        },
        photos: {
          orderBy: { createdAt: 'asc' },
          include: { uploadedBy: { select: { id: true, displayName: true } } },
        },
      },
    });
    if (!seal) throw notFound('Ucpávka nenalezena');
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.post('/', requirePermission('seal.create'), async (req, res, next) => {
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
        internalNote: body.internalNote,
        openingLengthMm: body.openingLengthMm ?? null,
        openingWidthMm: body.openingWidthMm ?? null,
        status: SealStatus.draft,
        createdById: req.user!.id,
        updatedById: req.user!.id,
        entries: {
          create: body.entries.map((e, i) => entryCreateData(e, i)),
        },
      },
      include: {
        entries: { include: { materials: true } },
        photos: true,
        createdBy: { select: { id: true, displayName: true } },
        updatedBy: { select: { id: true, displayName: true } },
      },
    });

    await logActivity(req.user!.id, 'create', 'seal', seal.id);
    await touchJobParticipant(body.jobId, req.user!.id, 'worker');
    await priceSealEntries(seal.id, req.user!.id);
    const priced = await prisma.seal.findFirst({
      where: { id: seal.id },
      include: {
        entries: { where: { deletedAt: null }, include: { materials: true } },
        photos: true,
        createdBy: { select: { id: true, displayName: true } },
        updatedBy: { select: { id: true, displayName: true } },
      },
    });
    res.status(201).json(priced);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id', requirePermission('seal.edit'), async (req, res, next) => {
  try {
    const body = sealBodySchema.partial().extend({
      entries: z.array(sealEntrySchema).optional(),
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
    const fields = [
      'sealNumber',
      'system',
      'construction',
      'location',
      'fireRating',
      'note',
      'internalNote',
      'openingLengthMm',
      'openingWidthMm',
    ] as const;
    for (const f of fields) {
      if (body[f] !== undefined) {
        if (String(existing[f]) !== String(body[f])) {
          await logChange(req.user!.id, 'seal', existing.id, f, String(existing[f] ?? ''), String(body[f]));
        }
        updateData[f] = body[f];
      }
    }

    if (body.entries) {
      await logChange(req.user!.id, 'seal', existing.id, 'entries', 'updated', 'updated');
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
              itemLengthMm: e.itemLengthMm ?? null,
              itemWidthMm: e.itemWidthMm ?? null,
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
      await priceSealEntries(existing.id, req.user!.id);
    }

    const seal = await prisma.seal.update({
      where: { id: existing.id },
      data: updateData,
      include: {
        entries: { where: { deletedAt: null }, include: { materials: true } },
        photos: true,
        createdBy: { select: { id: true, displayName: true } },
        updatedBy: { select: { id: true, displayName: true } },
      },
    });

    await logActivity(req.user!.id, 'update', 'seal', seal.id);
    await touchJobParticipant(existing.jobId, req.user!.id, 'worker');
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/status', requirePermission('seal.status'), async (req, res, next) => {
  try {
    const body = z
      .object({
        status: z.nativeEnum(SealStatus),
        comment: z.string().optional(),
      })
      .parse(req.body);
    const seal = await changeSealStatus(
      paramId(req.params.id),
      body.status,
      req.user!.id,
      req.user!.role,
      body.comment,
    );
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.delete('/:id', requirePermission('seal.delete'), async (req, res, next) => {
  try {
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
