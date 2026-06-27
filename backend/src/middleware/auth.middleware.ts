import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { UserRole, MaterialMode } from '@prisma/client';
import { config } from '../config.js';
import { prisma } from '../lib/prisma.js';
import { AppError, unauthorized, forbidden } from '../lib/errors.js';
import { hashSessionToken } from '../lib/session-token.js';

export interface AuthUser {
  id: string;
  username: string;
  displayName: string;
  role: UserRole;
  materialMode: MaterialMode;
  sessionId: string;
  mfaVerifiedAt?: Date;
  authMethod: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export async function authMiddleware(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return next(unauthorized());
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, config.jwtSecret) as { sub: string; sid: string };
    const session = await prisma.userSession.findFirst({
      where: { id: payload.sid, token: hashSessionToken(token), expiresAt: { gt: new Date() } },
      include: { user: true },
    });
    if (!session || !session.user.isActive) {
      return next(unauthorized('Neplatná session'));
    }
    req.user = {
      id: session.user.id,
      username: session.user.username,
      displayName: session.user.displayName,
      role: session.user.role,
      materialMode: session.user.materialMode,
      sessionId: session.id,
      mfaVerifiedAt: session.mfaVerifiedAt ?? undefined,
      authMethod: session.authMethod,
    };
    next();
  } catch {
    next(unauthorized());
  }
}

export function requireRecentAdminMfa(req: Request, _res: Response, next: NextFunction) {
  if (!req.user) return next(unauthorized());
  if (req.user.role !== UserRole.admin || !config.adminMfa.required) return next();
  const verifiedAt = req.user.mfaVerifiedAt;
  const maxAgeMs = config.adminMfa.stepUpMinutes * 60 * 1000;
  if (!verifiedAt || Date.now() - verifiedAt.getTime() > maxAgeMs) {
    return next(new AppError(403, 'STEP_UP_REQUIRED', 'Pro tuto operaci je nutné znovu ověřit MFA'));
  }
  next();
}

export function requireRole(...roles: UserRole[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) return next(unauthorized());
    if (!roles.includes(req.user.role)) return next(forbidden());
    next();
  };
}
