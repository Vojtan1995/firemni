import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { UserRole } from '@prisma/client';
import { config } from '../config.js';
import { prisma } from '../lib/prisma.js';
import { unauthorized, forbidden } from '../lib/errors.js';
import { hashSessionToken } from '../lib/session-token.js';

export interface AuthUser {
  id: string;
  username: string;
  displayName: string;
  role: UserRole;
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
    };
    next();
  } catch {
    next(unauthorized());
  }
}

export function requireRole(...roles: UserRole[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) return next(unauthorized());
    if (!roles.includes(req.user.role)) return next(forbidden());
    next();
  };
}

export function optionalAuth(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return next();
  authMiddleware(req, _res, next).catch(next);
}
