import { Router } from 'express';
import { badRequest } from '../lib/errors.js';
import { getAppReleasePayload } from '../services/app-release.service.js';

const router = Router();

router.get('/release', (req, res, next) => {
  try {
    const platform = typeof req.query.platform === 'string' ? req.query.platform : '';
    if (!platform) {
      throw badRequest('Query parameter platform is required');
    }

    const payload = getAppReleasePayload(platform);
    if ('error' in payload && payload.error === 'unsupported_platform') {
      throw badRequest('Unsupported platform');
    }

    res.json(payload);
  } catch (e) {
    next(e);
  }
});

export default router;
