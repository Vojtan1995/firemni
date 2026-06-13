import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { unauthorized, forbidden } from '../lib/errors.js';
import { AppError } from '../lib/errors.js';
import { hashSessionToken } from '../lib/session-token.js';
import { logActivity } from './audit.service.js';

const LOCKOUT_WINDOW_MS = 15 * 60 * 1000; // 15 minut
const LOCKOUT_MAX_ATTEMPTS = 10;

async function checkAccountLockout(username: string): Promise<void> {
  const since = new Date(Date.now() - LOCKOUT_WINDOW_MS);
  const recentFailures = await prisma.loginLog.count({
    where: { username, success: false, createdAt: { gte: since } },
  });
  if (recentFailures >= LOCKOUT_MAX_ATTEMPTS) {
    throw new AppError(429, 'ACCOUNT_LOCKED', 'Účet je dočasně zablokován kvůli příliš mnoha neúspěšným pokusům. Zkuste to za 15 minut.');
  }
}

export async function login(username: string, pin: string, meta?: { ip?: string; userAgent?: string }) {
  // Zkontroluj lockout před načtením uživatele (brání user enumeration přes timing)
  await checkAccountLockout(username);

  const user = await prisma.user.findUnique({ where: { username } });

  if (!user || !user.isActive) {
    await prisma.loginLog.create({
      data: { userId: user?.id, username, success: false, ipAddress: meta?.ip, userAgent: meta?.userAgent },
    });
    throw unauthorized('Neplatné přihlašovací údaje');
  }

  const valid = await bcrypt.compare(pin, user.pinHash);
  if (!valid) {
    await prisma.loginLog.create({
      data: { userId: user.id, username, success: false, ipAddress: meta?.ip, userAgent: meta?.userAgent },
    });
    throw unauthorized('Neplatné přihlašovací údaje');
  }

  await prisma.loginLog.create({
    data: { userId: user.id, username, success: true, ipAddress: meta?.ip, userAgent: meta?.userAgent },
  });

  const sessionId = uuidv4();
  const token = jwt.sign({ sub: user.id, sid: sessionId }, config.jwtSecret, {
    expiresIn: `${config.sessionDays}d`,
  });

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + config.sessionDays);

  await prisma.userSession.create({
    data: { id: sessionId, userId: user.id, token: hashSessionToken(token), expiresAt },
  });

  await logActivity(user.id, 'login', 'user', user.id);

  return {
    token,
    user: {
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      role: user.role,
      mustChangePin: user.mustChangePin,
    },
  };
}

export async function logout(token: string, userId: string) {
  await prisma.userSession.deleteMany({ where: { token: hashSessionToken(token), userId } });
  await logActivity(userId, 'logout', 'user', userId);
}

export async function getMe(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || !user.isActive) throw forbidden('Účet deaktivován');
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    role: user.role,
    mustChangePin: user.mustChangePin,
  };
}

export async function changeOwnPin(userId: string, currentPin: string, newPin: string, currentToken: string) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || !user.isActive) throw forbidden('Účet deaktivován');

  const valid = await bcrypt.compare(currentPin, user.pinHash);
  if (!valid) throw unauthorized('Aktuální PIN není správný');

  const samePin = await bcrypt.compare(newPin, user.pinHash);
  if (samePin) throw forbidden('Nový PIN musí být jiný než aktuální PIN');

  const pinHash = await bcrypt.hash(newPin, 10);
  const updated = await prisma.user.update({
    where: { id: userId },
    data: { pinHash, mustChangePin: false },
  });

  await prisma.userSession.deleteMany({
    where: { userId, token: { not: hashSessionToken(currentToken) } },
  });
  await logActivity(userId, 'change_pin', 'user', userId);

  return {
    id: updated.id,
    username: updated.username,
    displayName: updated.displayName,
    role: updated.role,
    mustChangePin: updated.mustChangePin,
  };
}
