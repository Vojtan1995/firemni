import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../lib/errors.js';
import { logError } from '../services/audit.service.js';
import { logger } from '../lib/logger.js';
import { redactText, redactUnknown } from '../lib/redaction.js';

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

  const message = redactText(
    err instanceof Error ? err.message : 'Interní chyba serveru',
    2000,
  )!;
  logger.error(
    {
      error: redactUnknown(
        err instanceof Error
          ? { name: err.name, message: err.message, stack: err.stack }
          : err,
      ),
      path: redactText(req.path, 500),
    },
    message,
  );
  logError(message, {
    stack: redactText(err instanceof Error ? err.stack : undefined),
    path: redactText(req.path, 500),
    method: req.method,
    userId: req.user?.id,
  }).catch(() => {});

  res.status(500).json({ error: 'Interní chyba serveru', code: 'INTERNAL_ERROR' });
}
