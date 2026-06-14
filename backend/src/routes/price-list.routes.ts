import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { notFound } from '../lib/errors.js';
import {
  getActivePriceList,
  getPriceListByVersion,
  listPriceListVersions,
  publishPriceListChanges,
  seedDefaultPriceList,
} from '../services/pricing.service.js';

const router = Router();
router.use(authMiddleware);

const publishItemSchema = z.object({
  id: z.string().uuid().optional(),
  category: z.string().min(1).max(100),
  sizeLabel: z.string().min(1).max(100),
  unit: z.string().min(1).max(100).default('kus'),
  priceWithMaterial: z.number().nonnegative(),
  priceWithoutMaterial: z.number().nonnegative().nullable().optional(),
  active: z.boolean().optional(),
  sortOrder: z.number().int().optional(),
});

const publishSchema = z.object({
  items: z.array(publishItemSchema).min(1),
});

router.get('/versions', requirePermission('priceList.view'), async (_req, res, next) => {
  try {
    const versions = await listPriceListVersions();
    res.json(versions);
  } catch (e) {
    next(e);
  }
});

router.get('/versions/:version', requirePermission('priceList.view'), async (req, res, next) => {
  try {
    const version = String(req.params.version);
    const list = await getPriceListByVersion(version);
    res.json(list);
  } catch (e) {
    next(e);
  }
});

router.get('/', requirePermission('priceList.view'), async (_req, res, next) => {
  try {
    const list = await getActivePriceList();
    if (!list) {
      throw notFound('Aktivní ceník není k dispozici');
    }
    res.json(list);
  } catch (e) {
    next(e);
  }
});

router.post('/publish', requirePermission('priceList.manage'), async (req, res, next) => {
  try {
    const body = publishSchema.parse(req.body);
    const list = await publishPriceListChanges(req.user!.id, body.items);
    res.status(201).json(list);
  } catch (e) {
    next(e);
  }
});

router.post('/seed', requirePermission('job.manage'), async (_req, res, next) => {
  try {
    const list = await seedDefaultPriceList();
    res.json(list);
  } catch (e) {
    next(e);
  }
});

export default router;
