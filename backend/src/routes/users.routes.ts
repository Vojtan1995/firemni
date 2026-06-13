import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { logActivity } from '../services/audit.service.js';
import * as userService from '../services/user.service.js';
import { paramId } from '../lib/params.js';

const router = Router();
router.use(authMiddleware);
router.use(requirePermission('user.manage'));

const pinSchema = z.string().min(6).max(8);

const createUserSchema = z.object({
  username: z.string().min(1).max(64),
  displayName: z.string().min(1),
  pin: pinSchema,
  role: z.nativeEnum(UserRole),
});

const updateUserSchema = z.object({
  displayName: z.string().min(1).optional(),
  pin: pinSchema.optional(),
  role: z.nativeEnum(UserRole).optional(),
  isActive: z.boolean().optional(),
});

router.get('/', async (req, res, next) => {
  try {
    const users = await userService.listUsers(req.user!.role);
    res.json(users);
  } catch (e) {
    next(e);
  }
});

router.post('/', async (req, res, next) => {
  try {
    const body = createUserSchema.parse(req.body);
    const user = await userService.createUser(req.user!.role, body);
    await logActivity(req.user!.id, 'create', 'user', user.id);
    res.status(201).json(user);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id', async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    const body = updateUserSchema.parse(req.body);
    const user = await userService.updateUser(req.user!.role, req.user!.id, id, body);
    await logActivity(req.user!.id, 'update', 'user', user.id);
    res.json(user);
  } catch (e) {
    next(e);
  }
});

export default router;
