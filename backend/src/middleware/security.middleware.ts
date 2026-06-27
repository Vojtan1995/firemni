import rateLimit from 'express-rate-limit';
import { UserRole } from '@prisma/client';
import { config } from '../config.js';

export const loginRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Příliš mnoho pokusů o přihlášení, zkuste to později' },
  skip: () => config.nodeEnv === 'test',
});

export const jobNumberRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user!.id,
  message: {
    error: 'Příliš mnoho pokusů o otevření stavby, zkuste to později',
    code: 'RATE_LIMITED',
  },
  skip: (req) => config.nodeEnv === 'test' || req.user?.role !== UserRole.worker,
});

// Per-uživatel limit pro odesílání zpráv (anti-spam). 60/15 min je pro lidskou
// komunikaci dostatečné a zároveň brání zahlcení DB i příjemců.
export const messageRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user!.id,
  message: {
    error: 'Příliš mnoho odeslaných zpráv, zkuste to později',
    code: 'RATE_LIMITED',
  },
  skip: () => config.nodeEnv === 'test',
});

// Per-uživatel limit pro sync push. Automatický sync (FE-06) běží v intervalu
// ~15 s (≈60/15 min); 300/15 min nechává rezervu pro ruční sync a více zařízení,
// ale brání smyčce, která by zaplavila server zápisy.
export const syncPushRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user!.id,
  message: {
    error: 'Příliš mnoho synchronizací, zkuste to za chvíli',
    code: 'RATE_LIMITED',
  },
  skip: () => config.nodeEnv === 'test',
});

// Per-uživatel limit pro CPU-náročné exporty (CSV/PDF přes canvas/pdfkit).
// 40/15 min pokryje běžné použití, ale brání DoS opakovaným generováním PDF.
export const exportRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user!.id,
  message: {
    error: 'Příliš mnoho exportů, zkuste to za chvíli',
    code: 'RATE_LIMITED',
  },
  skip: () => config.nodeEnv === 'test',
});

export const mfaRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Příliš mnoho MFA pokusů, zkuste to později',
    code: 'MFA_RATE_LIMITED',
  },
  skip: () => config.nodeEnv === 'test',
});
