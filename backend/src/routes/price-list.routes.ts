import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { getActivePriceList, seedDefaultPriceList } from '../services/pricing.service.js';

const router = Router();
router.use(authMiddleware);

router.get('/', requirePermission('priceList.view'), async (_req, res, next) => {
  try {
    let list = await getActivePriceList();
    if (!list) {
      list = await seedDefaultPriceList();
    }
    res.json(list);
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
