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
