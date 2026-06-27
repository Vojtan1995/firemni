import { Router } from 'express';
import { z } from 'zod';
import { UserRole, MaterialMode } from '@prisma/client';
import { authMiddleware, requireRecentAdminMfa } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { logActivity } from '../services/audit.service.js';
import * as userService from '../services/user.service.js';
import { paramId } from '../lib/params.js';
import * as mfaService from '../services/mfa.service.js';
import * as privacyService from '../services/privacy.service.js';

const router = Router();
router.use(authMiddleware);
router.use(requirePermission('user.manage'));

const pinSchema = z.string().min(6).max(128);

const createUserSchema = z.object({
  username: z.string().min(1).max(64),
  displayName: z.string().min(1).max(100),
  pin: pinSchema,
  role: z.nativeEnum(UserRole),
  materialMode: z.nativeEnum(MaterialMode).optional(),
});

const updateUserSchema = z.object({
  displayName: z.string().min(1).max(100).optional(),
  pin: pinSchema.optional(),
  role: z.nativeEnum(UserRole).optional(),
  isActive: z.boolean().optional(),
  materialMode: z.nativeEnum(MaterialMode).optional(),
});

router.get('/', async (req, res, next) => {
  try {
    const users = await userService.listUsers(req.user!.role);
    res.json(users);
  } catch (e) {
    next(e);
  }
});

router.post('/', requireRecentAdminMfa, async (req, res, next) => {
  try {
    const body = createUserSchema.parse(req.body);
    const user = await userService.createUser(req.user!.role, body);
    await logActivity(req.user!.id, 'create', 'user', user.id);
    res.status(201).json(user);
  } catch (e) {
    next(e);
  }
});

router.patch('/:id', requireRecentAdminMfa, async (req, res, next) => {
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

// GDPR výmaz osobních údajů (anonymizace). Pouze admin – kontrola v service.
router.delete('/:id', requireRecentAdminMfa, async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    await userService.anonymizeUser(req.user!.role, req.user!.id, id);
    await logActivity(req.user!.id, 'anonymize', 'user', id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});

router.post('/:id/mfa-reset', requireRecentAdminMfa, async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    await mfaService.resetMfa(req.user!.id, id);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
});

router.get('/:id/privacy-export', requireRecentAdminMfa, async (req, res, next) => {
  try {
    const id = paramId(req.params.id);
    const data = await privacyService.exportUserPersonalData(
      req.user!.role,
      req.user!.id,
      id,
    );
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="privacy-export-${id}.json"`,
    );
    res.json(data);
  } catch (e) {
    next(e);
  }
});

export default router;
