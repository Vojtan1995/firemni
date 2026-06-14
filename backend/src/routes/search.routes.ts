import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { searchApp } from '../services/search.service.js';

const router = Router();
router.use(authMiddleware);

const querySchema = z.object({
  q: z.string().max(100).optional(),
  limit: z.coerce.number().int().min(1).max(50).optional(),
  offset: z.coerce.number().int().min(0).optional(),
  jobId: z.string().uuid().optional(),
  floorId: z.string().uuid().optional(),
  filters: z.union([z.string(), z.array(z.string())]).optional(),
});

router.get('/', async (req, res, next) => {
  try {
    const parsed = querySchema.parse(req.query);
    const result = await searchApp({
      role: req.user!.role,
      userId: req.user!.id,
      q: parsed.q,
      limit: parsed.limit,
      offset: parsed.offset,
      jobId: parsed.jobId,
      floorId: parsed.floorId,
      filters: parsed.filters,
    });
    res.json(result);
  } catch (e) {
    next(e);
  }
});

export default router;
