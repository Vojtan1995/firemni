import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { loginRateLimiter } from '../middleware/security.middleware.js';
import * as authService from '../services/auth.service.js';

const router = Router();

const loginSchema = z.object({
  username: z.string().min(1),
  pin: z.string().min(6).max(8),
});

const changePinSchema = z.object({
  currentPin: z.string().min(6).max(8),
  newPin: z.string().min(6).max(8),
});

router.post('/login', loginRateLimiter, async (req, res, next) => {
  try {
    const body = loginSchema.parse(req.body);
    const result = await authService.login(body.username, body.pin, {
      ip: req.ip,
      userAgent: req.get('user-agent') ?? undefined,
    });
    res.json(result);
  } catch (e) {
    next(e);
  }
});

router.post('/logout', authMiddleware, async (req, res, next) => {
  try {
    const token = req.headers.authorization!.slice(7);
    await authService.logout(token, req.user!.id);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

router.get('/me', authMiddleware, async (req, res, next) => {
  try {
    const user = await authService.getMe(req.user!.id);
    res.json(user);
  } catch (e) {
    next(e);
  }
});

router.post('/change-pin', authMiddleware, async (req, res, next) => {
  try {
    const body = changePinSchema.parse(req.body);
    const token = req.headers.authorization!.slice(7);
    const user = await authService.changeOwnPin(req.user!.id, body.currentPin, body.newPin, token);
    res.json(user);
  } catch (e) {
    next(e);
  }
});

export default router;
