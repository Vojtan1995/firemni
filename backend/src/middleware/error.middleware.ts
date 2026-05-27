import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../lib/errors.js';
import { logError } from '../services/audit.service.js';
import { logger } from '../lib/logger.js';

export function errorMiddleware(err: unknown, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({ error: err.message, code: err.code });
  }
  if (err instanceof ZodError) {
    return res.status(400).json({
      error: 'Validační chyba',
      code: 'VALIDATION_ERROR',
      details: err.flatten(),
    });
  }

  const message = err instanceof Error ? err.message : 'Interní chyba serveru';
  logger.error({ err, path: req.path }, message);
  logError(message, {
    stack: err instanceof Error ? err.stack : undefined,
    path: req.path,
    method: req.method,
    userId: req.user?.id,
  }).catch(() => {});

  res.status(500).json({ error: 'Interní chyba serveru', code: 'INTERNAL_ERROR' });
}
