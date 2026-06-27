import bcrypt from 'bcrypt';
import { UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { unauthorized, forbidden } from '../lib/errors.js';
import { AppError } from '../lib/errors.js';
import { hashSessionToken } from '../lib/session-token.js';
import { logActivity } from './audit.service.js';
import { createAuthenticatedSession } from './session.service.js';
import { assertStrongAdminPassword, beginAdminMfa } from './mfa.service.js';

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

export async function login(username: string, credential: string, meta?: { ip?: string; userAgent?: string }) {
  // Zkontroluj lockout před načtením uživatele (brání user enumeration přes timing)
  await checkAccountLockout(username);

  const user = await prisma.user.findUnique({ where: { username } });

  if (!user || !user.isActive) {
    await prisma.loginLog.create({
      data: { userId: user?.id, username, success: false, ipAddress: meta?.ip, userAgent: meta?.userAgent },
    });
    throw unauthorized('Neplatné přihlašovací údaje');
  }

  const isAdmin = user.role === UserRole.admin;
  const credentialHash = isAdmin && user.passwordHash ? user.passwordHash : user.pinHash;
  const valid = await bcrypt.compare(credential, credentialHash);
  if (!valid) {
    await prisma.loginLog.create({
      data: { userId: user.id, username, success: false, ipAddress: meta?.ip, userAgent: meta?.userAgent },
    });
    throw unauthorized('Neplatné přihlašovací údaje');
  }

  await prisma.loginLog.create({
    data: { userId: user.id, username, success: true, ipAddress: meta?.ip, userAgent: meta?.userAgent },
  });

  if (isAdmin && config.adminMfa.required && !user.passwordHash) {
    throw new AppError(
      428,
      'ADMIN_PASSWORD_SETUP_REQUIRED',
      'Admin musí před aktivací MFA nastavit heslo o délce alespoň 12 znaků',
    );
  }
  const mfa = isAdmin
    ? await prisma.userMfaCredential.findUnique({ where: { userId: user.id } })
    : null;
  if (isAdmin && (config.adminMfa.required || mfa?.enabledAt)) {
    return beginAdminMfa(user);
  }

  await logActivity(user.id, 'login', 'user', user.id);
  return createAuthenticatedSession(
    user.id,
    isAdmin && user.passwordHash ? 'password' : 'pin',
  );
}

export async function logout(token: string, userId: string) {
  await prisma.userSession.deleteMany({ where: { token: hashSessionToken(token), userId } });
  await logActivity(userId, 'logout', 'user', userId);
}

export async function getMe(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { mfaCredential: { select: { enabledAt: true } } },
  });
  if (!user || !user.isActive) throw forbidden('Účet deaktivován');
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    role: user.role,
    materialMode: user.materialMode,
    mustChangePin: user.mustChangePin,
    mfaEnabled: user.mfaCredential?.enabledAt != null,
  };
}

export async function changeOwnPin(userId: string, currentPin: string, newPin: string, currentToken: string) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || !user.isActive) throw forbidden('Účet deaktivován');

  const currentHash =
    user.role === UserRole.admin && user.passwordHash ? user.passwordHash : user.pinHash;
  const valid = await bcrypt.compare(currentPin, currentHash);
  if (!valid) throw unauthorized('Aktuální PIN není správný');

  const samePin = await bcrypt.compare(newPin, currentHash);
  if (samePin) throw forbidden('Nový PIN musí být jiný než aktuální PIN');

  if (user.role === UserRole.admin) assertStrongAdminPassword(newPin);
  const nextHash = await bcrypt.hash(newPin, 10);
  const updated = await prisma.user.update({
    where: { id: userId },
    data:
      user.role === UserRole.admin
        ? { passwordHash: nextHash, mustChangePin: false }
        : { pinHash: nextHash, mustChangePin: false },
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
    materialMode: updated.materialMode,
    mustChangePin: updated.mustChangePin,
  };
}
