import { Router } from 'express';
import { z } from 'zod';
import { WorkSheetStatus } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { paramId } from '../lib/params.js';
import {
  addWorksheetItems,
  changeWorksheetStatus,
  createWorksheet,
  exportWorksheetCsv,
  exportWorksheetPdf,
  getWorksheet,
  listWorksheets,
  populateWorksheetFromFilters,
} from '../services/worksheet.service.js';

const router = Router();
router.use(authMiddleware);
router.use(requirePermission('worksheet.view', 'worksheet.create'));

router.get('/', async (req, res, next) => {
  try {
    const query = req.query as Record<string, string>;
    const status = query.status ? (query.status as WorkSheetStatus) : undefined;
    const worksheets = await listWorksheets(req.user!.role, req.user!.id, {
      jobId: query.jobId,
      status,
      workerId: query.workerId,
      floorId: query.floorId,
      from: query.from,
      to: query.to,
      invoiced:
        query.invoiced === 'true'
          ? true
          : query.invoiced === 'false'
            ? false
            : undefined,
    });
    res.json(worksheets);
  } catch (e) {
    next(e);
  }
});

router.post('/', requirePermission('worksheet.create'), async (req, res, next) => {
  try {
    const body = z
      .object({
        jobId: z.string().uuid(),
        workerIds: z.array(z.string().uuid()).optional(),
        periodFrom: z.string().optional(),
        periodTo: z.string().optional(),
        note: z.string().optional(),
      })
      .parse(req.body);
    const worksheet = await createWorksheet(req.user!.role, req.user!.id, body);
    res.status(201).json(worksheet);
  } catch (e) {
    next(e);
  }
});

router.get('/:id/export/csv', async (req, res, next) => {
  try {
    const { csv, filename } = await exportWorksheetCsv(
      paramId(req.params.id),
      req.user!.role,
      req.user!.id,
    );
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.send(csv);
  } catch (e) {
    next(e);
  }
});

router.get('/:id/export/pdf', async (req, res, next) => {
  try {
    await exportWorksheetPdf(paramId(req.params.id), req.user!.role, req.user!.id, res);
  } catch (e) {
    next(e);
  }
});

router.get('/:id', async (req, res, next) => {
  try {
    const worksheet = await getWorksheet(paramId(req.params.id), req.user!.role, req.user!.id);
    res.json(worksheet);
  } catch (e) {
    next(e);
  }
});

router.post('/:id/items', requirePermission('worksheet.create'), async (req, res, next) => {
  try {
    const body = z
      .object({
        sealEntryIds: z.array(z.string().uuid()).min(1),
      })
      .parse(req.body);
    const items = await addWorksheetItems(
      paramId(req.params.id),
      req.user!.role,
      req.user!.id,
      body.sealEntryIds,
    );
    res.status(201).json(items);
  } catch (e) {
    next(e);
  }
});

router.post('/:id/populate', requirePermission('worksheet.create'), async (req, res, next) => {
  try {
    const body = z
      .object({
        floorIds: z.array(z.string().uuid()).optional(),
        status: z.string().optional(),
        from: z.string().optional(),
        to: z.string().optional(),
      })
      .parse(req.body);
    const items = await populateWorksheetFromFilters(
      paramId(req.params.id),
      req.user!.role,
      req.user!.id,
      body,
    );
    res.status(201).json(items);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/status', async (req, res, next) => {
  try {
    const body = z
      .object({
        status: z.nativeEnum(WorkSheetStatus),
        comment: z.string().max(500).optional(),
      })
      .parse(req.body);
    const worksheet = await changeWorksheetStatus(
      paramId(req.params.id),
      body.status,
      req.user!.role,
      req.user!.id,
      body.comment,
    );
    res.json(worksheet);
  } catch (e) {
    next(e);
  }
});

export default router;
