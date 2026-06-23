import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { paramId } from '../lib/params.js';
import { repairBodySchema } from '../lib/repair-schemas.js';
import {
  buildRepairsCsv,
  createSealRepair,
  getRepairDetail,
  listRepairs,
} from '../services/repair.service.js';

const router = Router();
router.use(authMiddleware);

router.get('/', requirePermission('repair.view'), async (req, res, next) => {
  try {
    const repairs = await listRepairs(req.user!.role, req.user!.id);
    res.json(repairs);
  } catch (e) {
    next(e);
  }
});

router.post(
  '/bulk-export/csv',
  requirePermission('repair.export'),
  async (req, res, next) => {
    try {
      const body = z
        .object({ ids: z.array(z.string().uuid()).min(1) })
        .parse(req.body);
      const csv = await buildRepairsCsv(body.ids, req.user!.id, req.user!.role);
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader(
        'Content-Disposition',
        'attachment; filename="vybrane-opravy.csv"',
      );
      res.send(csv);
    } catch (e) {
      next(e);
    }
  },
);

router.get('/:id', requirePermission('repair.view'), async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    const repair = await getRepairDetail(id, req.user!.role, req.user!.id);
    res.json(repair);
  } catch (e) {
    next(e);
  }
});

router.post('/', requirePermission('repair.create'), async (req, res, next) => {
  try {
    const body = repairBodySchema.parse(req.body);
    const repair = await createSealRepair(
      body.sealId,
      req.user!.id,
      req.user!.role,
      body,
    );
    res.status(201).json(repair);
  } catch (e) {
    next(e);
  }
});

export default router;
