import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth.middleware.js';
import * as privacyService from '../services/privacy.service.js';

const router = Router();
router.use(authMiddleware);

router.get('/notice', async (req, res, next) => {
  try {
    res.json(await privacyService.getPrivacyNotice(req.user!.id));
  } catch (e) {
    next(e);
  }
});

router.post('/notice/accept', async (req, res, next) => {
  try {
    const body = z.object({ version: z.string().min(1).max(100) }).parse(req.body);
    res.json(await privacyService.acceptPrivacyNotice(req.user!.id, body.version));
  } catch (e) {
    next(e);
  }
});

export default router;
