import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { paramId } from '../lib/params.js';
import {
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  unreadNotificationCount,
} from '../services/notification.service.js';

const router = Router();
router.use(authMiddleware);

router.get('/', async (req, res, next) => {
  try {
    const rows = await listNotifications(req.user!.id);
    res.json(rows);
  } catch (e) {
    next(e);
  }
});

router.get('/unread-count', async (req, res, next) => {
  try {
    const count = await unreadNotificationCount(req.user!.id);
    res.json({ count });
  } catch (e) {
    next(e);
  }
});

router.patch('/read-all', async (req, res, next) => {
  try {
    await markAllNotificationsRead(req.user!.id);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

router.patch('/:id/read', async (req, res, next) => {
  try {
    const row = await markNotificationRead(req.user!.id, paramId(req.params.id));
    res.json(row ?? { ok: false });
  } catch (e) {
    next(e);
  }
});

export default router;
