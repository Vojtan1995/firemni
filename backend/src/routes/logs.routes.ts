import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { prisma } from '../lib/prisma.js';

const router = Router();
router.use(authMiddleware);
router.use(requirePermission('logs.view'));

router.get('/activity', async (req, res, next) => {
  try {
    const since = req.query.since ? new Date(String(req.query.since)) : undefined;
    const userId = req.query.userId as string | undefined;
    const entityType = req.query.entityType as string | undefined;

    const logs = await prisma.activityLog.findMany({
      where: {
        ...(since ? { createdAt: { gte: since } } : {}),
        ...(userId ? { userId } : {}),
        ...(entityType ? { entityType } : {}),
      },
      include: { user: { select: { displayName: true, username: true } } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(logs);
  } catch (e) {
    next(e);
  }
});

router.get('/changes', async (req, res, next) => {
  try {
    const entityId = req.query.entityId as string | undefined;
    const logs = await prisma.changeLog.findMany({
      where: entityId ? { entityId } : {},
      include: { user: { select: { displayName: true } } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(logs);
  } catch (e) {
    next(e);
  }
});

export default router;
