import rateLimit from 'express-rate-limit';
import { config } from '../config.js';

export const loginRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Příliš mnoho pokusů o přihlášení, zkuste to později' },
  skip: () => config.nodeEnv === 'test',
});
