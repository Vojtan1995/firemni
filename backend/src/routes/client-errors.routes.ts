import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { logError } from '../services/audit.service.js';

const router = Router();
router.use(authMiddleware);

const clientErrorSchema = z.object({
  message: z.string().min(1).max(2000),
  stack: z.string().max(20000).optional(),
  route: z.string().max(500).optional(),
  appVersion: z.string().max(100).optional(),
  platform: z.string().max(100).optional(),
});

// Hlášení chyby zachycené přímo v aplikaci u uživatele. Ukládá se do ErrorLog
// (metadata.source='client') a vedení ho vidí v Logách (Systém/sync).
router.post('/', async (req, res, next) => {
  try {
    const body = clientErrorSchema.parse(req.body);
    await logError(body.message, {
      stack: body.stack,
      path: body.route,
      method: 'CLIENT',
      userId: req.user!.id,
      metadata: {
        source: 'client',
        appVersion: body.appVersion,
        platform: body.platform,
      },
    });
    res.status(201).json({ ok: true });
  } catch (e) {
    next(e);
  }
});

export default router;
