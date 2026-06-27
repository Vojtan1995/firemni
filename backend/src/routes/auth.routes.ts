import { Router } from 'express';
import { z } from 'zod';
import { authMiddleware, requireRecentAdminMfa } from '../middleware/auth.middleware.js';
import { loginRateLimiter, mfaRateLimiter } from '../middleware/security.middleware.js';
import * as authService from '../services/auth.service.js';
import * as mfaService from '../services/mfa.service.js';

const router = Router();

const loginSchema = z.object({
  username: z.string().min(1),
  pin: z.string().min(6).max(128).optional(),
  credential: z.string().min(6).max(128).optional(),
}).refine((body) => body.credential != null || body.pin != null, {
  message: 'Chybí přihlašovací údaj',
});

const changePinSchema = z.object({
  currentPin: z.string().min(6).max(128),
  newPin: z.string().min(6).max(128),
});

const challengeSchema = z.object({
  challengeToken: z.string().min(20).max(200),
});
const verifyMfaSchema = challengeSchema.extend({
  code: z.string().min(6).max(64),
});

router.post('/login', loginRateLimiter, async (req, res, next) => {
  try {
    const body = loginSchema.parse(req.body);
    const result = await authService.login(body.username, body.credential ?? body.pin!, {
      ip: req.ip,
      userAgent: req.get('user-agent') ?? undefined,
    });
    res.json(result);
  } catch (e) {
    next(e);
  }
});

router.post('/mfa/enroll/start', mfaRateLimiter, async (req, res, next) => {
  try {
    const body = challengeSchema.parse(req.body);
    res.json(await mfaService.startEnrollment(body.challengeToken));
  } catch (e) {
    next(e);
  }
});

router.post('/mfa/enroll/confirm', mfaRateLimiter, async (req, res, next) => {
  try {
    const body = verifyMfaSchema.parse(req.body);
    res.json(await mfaService.confirmEnrollment(body.challengeToken, body.code));
  } catch (e) {
    next(e);
  }
});

router.post('/mfa/verify-login', mfaRateLimiter, async (req, res, next) => {
  try {
    const body = verifyMfaSchema.parse(req.body);
    res.json(await mfaService.verifyLogin(body.challengeToken, body.code));
  } catch (e) {
    next(e);
  }
});

router.post('/mfa/recovery', mfaRateLimiter, async (req, res, next) => {
  try {
    const body = verifyMfaSchema.parse(req.body);
    res.json(await mfaService.useRecoveryCode(body.challengeToken, body.code));
  } catch (e) {
    next(e);
  }
});

router.post('/mfa/step-up', authMiddleware, mfaRateLimiter, async (req, res, next) => {
  try {
    const body = z.object({ code: z.string().regex(/^\d{6}$/) }).parse(req.body);
    res.json(await mfaService.stepUp(req.user!.id, req.user!.sessionId, body.code));
  } catch (e) {
    next(e);
  }
});

router.post(
  '/mfa/regenerate-recovery-codes',
  authMiddleware,
  requireRecentAdminMfa,
  async (req, res, next) => {
    try {
      res.json(await mfaService.regenerateRecoveryCodes(req.user!.id));
    } catch (e) {
      next(e);
    }
  },
);

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
