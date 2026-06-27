import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { hashSessionToken } from '../lib/session-token.js';

export async function createAuthenticatedSession(
  userId: string,
  authMethod: 'pin' | 'password' | 'password_totp' | 'password_recovery',
  mfaVerifiedAt?: Date,
) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { mfaCredential: { select: { enabledAt: true } } },
  });
  if (!user || !user.isActive) throw new Error('Active user not found');

  const session = await prisma.userSession.create({
    data: {
      userId,
      token: `pending-${randomUUID()}`,
      expiresAt: new Date(Date.now() + config.sessionDays * 24 * 60 * 60 * 1000),
      authMethod,
      mfaVerifiedAt,
    },
  });
  const token = jwt.sign({ sub: user.id, sid: session.id }, config.jwtSecret, {
    expiresIn: `${config.sessionDays}d`,
  });
  await prisma.userSession.update({
    where: { id: session.id },
    data: { token: hashSessionToken(token) },
  });

  return {
    token,
    user: {
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      role: user.role,
      materialMode: user.materialMode,
      mustChangePin: user.mustChangePin,
      mfaEnabled: user.mfaCredential?.enabledAt != null,
    },
  };
}
