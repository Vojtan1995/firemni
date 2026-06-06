import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { getStatsOverview } from '../services/stats.service.js';

const router = Router();
router.use(authMiddleware);
router.use(requirePermission('stats.view'));

router.get('/overview', async (req, res, next) => {
  try {
    const scopeUserId =
      typeof req.query.userId === 'string' ? req.query.userId : undefined;
    const stats = await getStatsOverview(req.user!.role, req.user!.id, scopeUserId);
    res.json(stats);
  } catch (e) {
    next(e);
  }
});

export default router;
