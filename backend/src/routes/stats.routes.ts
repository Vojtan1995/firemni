import { Router } from 'express';
import { SealStatus } from '@prisma/client';
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
    const jobId = typeof req.query.jobId === 'string' ? req.query.jobId : undefined;
    const statusRaw = typeof req.query.status === 'string' ? req.query.status : undefined;
    const status =
      statusRaw && Object.values(SealStatus).includes(statusRaw as SealStatus)
        ? (statusRaw as SealStatus)
        : undefined;
    const stats = await getStatsOverview(req.user!.role, req.user!.id, scopeUserId, {
      jobId,
      status,
    });
    res.json(stats);
  } catch (e) {
    next(e);
  }
});

export default router;
