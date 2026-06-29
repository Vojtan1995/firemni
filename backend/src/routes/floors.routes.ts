import { Router, type NextFunction, type Request, type Response } from 'express';
import multer from 'multer';
import path from 'path';
import { z } from 'zod';
import { authMiddleware, requireRole } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { prisma } from '../lib/prisma.js';
import { AppError, badRequest, conflict, notFound } from '../lib/errors.js';
import { logActivity } from '../services/audit.service.js';
import { MANAGEMENT_ROLES } from '../services/seal.service.js';
import { paramId } from '../lib/params.js';
import { assertJobReadable } from '../services/authorization.service.js';
import {
  deleteFloorDrawing,
  deleteSealMarker,
  getFloorDrawingBundle,
  getFloorDrawingFile,
  getFloorPlacementStats,
  uploadFloorDrawing,
  upsertSealMarker,
} from '../services/floor-drawing.service.js';
import { exportFloorDrawingPdf } from '../services/floor-drawing-export.service.js';
import { suggestNextSealNumber } from '../services/seal.service.js';
import { SealStatus } from '@prisma/client';

const router = Router({ mergeParams: true });
router.use(authMiddleware);

const maxDrawingSizeBytes = 50 * 1024 * 1024;

function isAllowedDrawingMime(mimetype: string, originalname: string): boolean {
  const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/jpg', 'application/pdf'];
  if (allowed.includes(mimetype)) return true;
  if (mimetype === 'application/octet-stream' || mimetype === 'application/x-unknown') {
    const ext = path.extname(originalname).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.pdf'].includes(ext);
  }
  return false;
}

const drawingUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: maxDrawingSizeBytes },
  fileFilter: (_req, file, cb) => {
    if (isAllowedDrawingMime(file.mimetype, file.originalname)) cb(null, true);
    else cb(badRequest(`Nepodporovaný formát výkresu (${file.mimetype})`));
  },
});

function drawingUploadMiddleware(req: Request, res: Response, next: NextFunction) {
  drawingUpload.single('drawing')(req, res, (err) => {
    if (!err) return next();
    if (err instanceof AppError) return next(err);
    if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
      return next(
        new AppError(413, 'UPLOAD_TOO_LARGE', `Výkres nesmí být větší než ${maxDrawingSizeBytes} B`),
      );
    }
    return next(badRequest('Výkres se nepodařilo nahrát'));
  });
}

router.get('/', async (req, res, next) => {
  try {
    const jobId = paramId((req.params as { jobId: string }).jobId);
    await assertJobReadable(jobId, req.user!.role, req.user!.id);

    const floors = await prisma.jobFloor.findMany({
      where: { jobId, deletedAt: null },
      orderBy: { sortOrder: 'asc' },
      include: { drawing: { select: { id: true } } },
    });
    res.json(
      floors.map(({ drawing, ...floor }) => ({
        ...floor,
        hasDrawing: drawing != null,
      })),
    );
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

router.get('/:floorId/next-seal-number', async (req, res, next) => {
  try {
    const jobId = paramId((req.params as { jobId: string; floorId: string }).jobId);
    const floorId = paramId((req.params as { jobId: string; floorId: string }).floorId);
    await getActiveFloor(jobId, floorId);
    await assertJobReadable(jobId, req.user!.role, req.user!.id);
    const nextNumber = await suggestNextSealNumber(floorId);
    res.json({ nextSealNumber: nextNumber });
  } catch (e) {
    next(e);
  }
});

router.get('/:floorId/placement-stats', async (req, res, next) => {
  try {
    const floorId = paramId(req.params.floorId);
    const stats = await getFloorPlacementStats(floorId, req.user!.role, req.user!.id);
    res.json(stats);
  } catch (e) {
    next(e);
  }
});

router.get('/:floorId/drawing', async (req, res, next) => {
  try {
    const floorId = paramId(req.params.floorId);
    const bundle = await getFloorDrawingBundle(floorId, req.user!.role, req.user!.id);
    res.json(bundle);
  } catch (e) {
    next(e);
  }
});

router.get('/:floorId/drawing/file', async (req, res, next) => {
  try {
    const floorId = paramId(req.params.floorId);
    const file = await getFloorDrawingFile(floorId, req.user!.role, req.user!.id);
    // Obsah na dané filePath je neměnný (nový upload dostane nový filePath),
    // takže lze bezpečně dlouze cachovat a vracet 304 při opakovaném stažení.
    const etag = `"${file.filePath}-${file.updatedAt.getTime()}"`;
    res.set('Cache-Control', 'private, max-age=31536000, immutable');
    res.set('ETag', etag);
    if (req.headers['if-none-match'] === etag) {
      res.status(304).end();
      return;
    }
    res.type(file.mimeType);
    res.send(file.body);
  } catch (e) {
    next(e);
  }
});

router.post(
  '/:floorId/drawing',
  requirePermission('floor.drawing.manage'),
  drawingUploadMiddleware,
  async (req, res, next) => {
    try {
      const floorId = paramId(req.params.floorId);
      if (!req.file) throw badRequest('Chybí multipart pole „drawing“');
      const drawing = await uploadFloorDrawing(
        floorId,
        req.file,
        req.user!.id,
        req.user!.role,
      );
      res.status(201).json(drawing);
    } catch (e) {
      next(e);
    }
  },
);

router.get('/:floorId/drawing/export/pdf', async (req, res, next) => {
  try {
    const jobId = paramId((req.params as { jobId: string; floorId: string }).jobId);
    const floorId = paramId((req.params as { jobId: string; floorId: string }).floorId);
    const q = req.query as Record<string, string | undefined>;
    const sealIds = q.sealIds?.split(',').filter(Boolean);
    const reviewStatus =
      q.reviewStatus === 'returned' ? ('returned' as const) : undefined;
    await exportFloorDrawingPdf(
      jobId,
      floorId,
      req.user!.role,
      req.user!.id,
      res,
      {
        status: reviewStatus ? undefined : (q.status as SealStatus | undefined),
        reviewStatus,
        workerId: q.workerId,
        sealIds,
        from: q.from,
        to: q.to,
      },
    );
  } catch (e) {
    next(e);
  }
});

router.delete('/:floorId/drawing', requirePermission('floor.drawing.manage'), async (req, res, next) => {
  try {
    const floorId = paramId(req.params.floorId);
    const result = await deleteFloorDrawing(floorId, req.user!.id, req.user!.role);
    res.json(result);
  } catch (e) {
    next(e);
  }
});

router.put('/:floorId/markers/:sealId', async (req, res, next) => {
  try {
    const floorId = paramId(req.params.floorId);
    const sealId = paramId(req.params.sealId);
    const body = z
      .object({
        x: z.number().min(0).max(1),
        y: z.number().min(0).max(1),
      })
      .parse(req.body);
    const marker = await upsertSealMarker(
      floorId,
      sealId,
      body.x,
      body.y,
      req.user!.id,
      req.user!.role,
    );
    res.json(marker);
  } catch (e) {
    next(e);
  }
});

router.delete('/:floorId/markers/:sealId', async (req, res, next) => {
  try {
    const sealId = paramId(req.params.sealId);
    const result = await deleteSealMarker(sealId, req.user!.id, req.user!.role);
    res.json(result);
  } catch (e) {
    next(e);
  }
});

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
