import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { unauthorized, forbidden } from '../lib/errors.js';
import { logActivity } from './audit.service.js';

export async function login(username: string, pin: string, meta?: { ip?: string; userAgent?: string }) {
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
    data: { id: sessionId, userId: user.id, token, expiresAt },
  });

  await logActivity(user.id, 'login', 'user', user.id);

  return {
    token,
    user: {
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      role: user.role,
    },
  };
}

export async function logout(token: string, userId: string) {
  await prisma.userSession.deleteMany({ where: { token, userId } });
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
  };
}
