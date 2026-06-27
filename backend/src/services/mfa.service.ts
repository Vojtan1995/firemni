import bcrypt from 'bcrypt';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from 'node:crypto';
import { User, UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { AppError, badRequest, forbidden, unauthorized } from '../lib/errors.js';
import { createAuthenticatedSession } from './session.service.js';
import { logActivity } from './audit.service.js';
import { sendSecurityAlert } from './security-alert.service.js';

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const MAX_CHALLENGE_ATTEMPTS = 5;
const MAX_ACCOUNT_ATTEMPTS = 10;
const ACCOUNT_ATTEMPT_WINDOW_MS = 15 * 60_000;

function base32Encode(input: Buffer) {
  let bits = 0;
  let value = 0;
  let output = '';
  for (const byte of input) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += BASE32[(value << (5 - bits)) & 31];
  return output;
}

function base32Decode(input: string) {
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];
  for (const char of input.toUpperCase().replace(/=|\s|-/g, '')) {
    const index = BASE32.indexOf(char);
    if (index < 0) throw badRequest('Neplatný MFA secret');
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

function dataKey() {
  if (/^[A-Fa-f0-9]{64}$/.test(config.adminMfa.dataKey)) {
    return Buffer.from(config.adminMfa.dataKey, 'hex');
  }
  // Development/test fallback only. Production validation rejects it when MFA is required.
  return createHash('sha256').update(`mfa:${config.jwtSecret}`).digest();
}

function encryptSecret(secret: string) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', dataKey(), iv);
  const encrypted = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([Buffer.from([1]), iv, tag, encrypted]).toString('base64url');
}

function decryptSecret(payload: string) {
  const bytes = Buffer.from(payload, 'base64url');
  if (bytes.length < 30 || bytes[0] !== 1) throw new Error('Unsupported MFA ciphertext');
  const iv = bytes.subarray(1, 13);
  const tag = bytes.subarray(13, 29);
  const decipher = createDecipheriv('aes-256-gcm', dataKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(bytes.subarray(29)), decipher.final()]).toString('utf8');
}

function tokenHash(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

function totpForStep(secret: string, step: bigint) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(step);
  const digest = createHmac('sha1', base32Decode(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const value =
    (((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff)) %
    1_000_000;
  return value.toString().padStart(6, '0');
}

function verifyTotp(secret: string, code: string, lastUsedStep?: bigint | null) {
  if (!/^\d{6}$/.test(code)) return null;
  const current = BigInt(Math.floor(Date.now() / 30_000));
  for (const delta of [-1n, 0n, 1n]) {
    const step = current + delta;
    const expected = Buffer.from(totpForStep(secret, step));
    const supplied = Buffer.from(code);
    if (
      expected.length === supplied.length &&
      timingSafeEqual(expected, supplied) &&
      (lastUsedStep == null || step > lastUsedStep)
    ) {
      return step;
    }
  }
  return null;
}

async function issueChallenge(userId: string, kind: 'login' | 'enroll') {
  const token = randomBytes(32).toString('base64url');
  await prisma.authChallenge.create({
    data: {
      userId,
      tokenHash: tokenHash(token),
      kind,
      expiresAt: new Date(Date.now() + config.adminMfa.challengeMinutes * 60_000),
    },
  });
  return token;
}

async function getChallenge(token: string, expectedKind: 'login' | 'enroll') {
  const challenge = await prisma.authChallenge.findUnique({
    where: { tokenHash: tokenHash(token) },
    include: { user: true },
  });
  if (
    !challenge ||
    challenge.kind !== expectedKind ||
    challenge.consumedAt ||
    challenge.expiresAt <= new Date()
  ) {
    throw unauthorized('MFA challenge vypršela nebo je neplatná');
  }
  if (challenge.attempts >= MAX_CHALLENGE_ATTEMPTS) {
    throw new AppError(429, 'MFA_LOCKED', 'Příliš mnoho neúspěšných MFA pokusů');
  }
  await assertAccountAttemptLimit(challenge.userId);
  return challenge;
}

async function assertAccountAttemptLimit(userId: string) {
  const aggregate = await prisma.authChallenge.aggregate({
    where: {
      userId,
      createdAt: { gte: new Date(Date.now() - ACCOUNT_ATTEMPT_WINDOW_MS) },
    },
    _sum: { attempts: true },
  });
  if ((aggregate._sum.attempts ?? 0) >= MAX_ACCOUNT_ATTEMPTS) {
    throw new AppError(429, 'MFA_ACCOUNT_LOCKED', 'Příliš mnoho MFA pokusů');
  }
}

async function failedAttempt(id: string) {
  await prisma.authChallenge.update({ where: { id }, data: { attempts: { increment: 1 } } });
}

async function consumeChallenge(id: string) {
  await prisma.authChallenge.update({ where: { id }, data: { consumedAt: new Date() } });
}

function recoveryCode() {
  return `${randomBytes(4).toString('hex')}-${randomBytes(4).toString('hex')}`.toUpperCase();
}

async function replaceRecoveryCodes(userId: string) {
  const plain = Array.from({ length: 10 }, recoveryCode);
  const hashes = await Promise.all(plain.map((code) => bcrypt.hash(code, 10)));
  await prisma.$transaction([
    prisma.mfaRecoveryCode.deleteMany({ where: { userId } }),
    prisma.mfaRecoveryCode.createMany({
      data: hashes.map((codeHash) => ({ userId, codeHash })),
    }),
  ]);
  return plain;
}

export async function beginAdminMfa(user: User) {
  const credential = await prisma.userMfaCredential.findUnique({ where: { userId: user.id } });
  const enrollmentRequired = credential?.enabledAt == null;
  const challengeToken = await issueChallenge(user.id, enrollmentRequired ? 'enroll' : 'login');
  return {
    code: enrollmentRequired ? 'MFA_ENROLLMENT_REQUIRED' : 'MFA_REQUIRED',
    mfaRequired: true,
    enrollmentRequired,
    challengeToken,
    expiresInSeconds: config.adminMfa.challengeMinutes * 60,
  };
}

export async function startEnrollment(challengeToken: string) {
  const challenge = await getChallenge(challengeToken, 'enroll');
  const secret = base32Encode(randomBytes(20));
  await prisma.userMfaCredential.upsert({
    where: { userId: challenge.userId },
    update: { secretCiphertext: encryptSecret(secret), enabledAt: null, lastUsedStep: null },
    create: { userId: challenge.userId, secretCiphertext: encryptSecret(secret) },
  });
  const label = encodeURIComponent(`${config.adminMfa.issuer}:${challenge.user.username}`);
  const issuer = encodeURIComponent(config.adminMfa.issuer);
  return {
    secret,
    otpauthUri: `otpauth://totp/${label}?secret=${secret}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30`,
  };
}

export async function confirmEnrollment(challengeToken: string, code: string) {
  const challenge = await getChallenge(challengeToken, 'enroll');
  const credential = await prisma.userMfaCredential.findUnique({
    where: { userId: challenge.userId },
  });
  if (!credential) throw badRequest('MFA enrollment nebyl zahájen');
  const step = verifyTotp(decryptSecret(credential.secretCiphertext), code);
  if (step == null) {
    await failedAttempt(challenge.id);
    throw unauthorized('Neplatný ověřovací kód');
  }
  const recoveryCodes = await replaceRecoveryCodes(challenge.userId);
  await prisma.$transaction([
    prisma.userMfaCredential.update({
      where: { userId: challenge.userId },
      data: { enabledAt: new Date(), lastUsedStep: step },
    }),
    prisma.authChallenge.update({
      where: { id: challenge.id },
      data: { consumedAt: new Date() },
    }),
  ]);
  await logActivity(challenge.userId, 'mfa_enroll', 'user', challenge.userId);
  const session = await createAuthenticatedSession(
    challenge.userId,
    'password_totp',
    new Date(),
  );
  return { ...session, recoveryCodes };
}

export async function verifyLogin(challengeToken: string, code: string) {
  const challenge = await getChallenge(challengeToken, 'login');
  const credential = await prisma.userMfaCredential.findUnique({
    where: { userId: challenge.userId },
  });
  if (!credential?.enabledAt) throw unauthorized('MFA není aktivní');
  const step = verifyTotp(
    decryptSecret(credential.secretCiphertext),
    code,
    credential.lastUsedStep,
  );
  if (step == null) {
    await failedAttempt(challenge.id);
    throw unauthorized('Neplatný ověřovací kód');
  }
  await prisma.$transaction([
    prisma.userMfaCredential.update({
      where: { userId: challenge.userId },
      data: { lastUsedStep: step },
    }),
    prisma.authChallenge.update({
      where: { id: challenge.id },
      data: { consumedAt: new Date() },
    }),
  ]);
  await logActivity(challenge.userId, 'mfa_login', 'user', challenge.userId);
  return createAuthenticatedSession(challenge.userId, 'password_totp', new Date());
}

export async function useRecoveryCode(challengeToken: string, code: string) {
  const challenge = await getChallenge(challengeToken, 'login');
  const rows = await prisma.mfaRecoveryCode.findMany({
    where: { userId: challenge.userId, usedAt: null },
  });
  let matched: (typeof rows)[number] | undefined;
  for (const row of rows) {
    if (await bcrypt.compare(code.toUpperCase(), row.codeHash)) {
      matched = row;
      break;
    }
  }
  if (!matched) {
    await failedAttempt(challenge.id);
    throw unauthorized('Neplatný recovery kód');
  }
  await prisma.$transaction([
    prisma.mfaRecoveryCode.update({ where: { id: matched.id }, data: { usedAt: new Date() } }),
    prisma.authChallenge.update({
      where: { id: challenge.id },
      data: { consumedAt: new Date() },
    }),
  ]);
  await logActivity(challenge.userId, 'mfa_recovery_used', 'user', challenge.userId);
  await sendSecurityAlert('mfa_recovery_used');
  return createAuthenticatedSession(challenge.userId, 'password_recovery', new Date());
}

export async function stepUp(userId: string, sessionId: string, code: string) {
  const recent = new Date(Date.now() - ACCOUNT_ATTEMPT_WINDOW_MS);
  let attempt = await prisma.authChallenge.findFirst({
    where: { userId, kind: 'step_up', consumedAt: null, createdAt: { gte: recent } },
    orderBy: { createdAt: 'desc' },
  });
  if (!attempt) {
    attempt = await prisma.authChallenge.create({
      data: {
        userId,
        tokenHash: tokenHash(`step-up:${sessionId}:${randomBytes(16).toString('hex')}`),
        kind: 'step_up',
        expiresAt: new Date(Date.now() + ACCOUNT_ATTEMPT_WINDOW_MS),
      },
    });
  }
  if (attempt.expiresAt <= new Date() || attempt.attempts >= MAX_CHALLENGE_ATTEMPTS) {
    throw new AppError(429, 'MFA_LOCKED', 'Příliš mnoho neúspěšných MFA pokusů');
  }
  await assertAccountAttemptLimit(userId);
  const credential = await prisma.userMfaCredential.findUnique({ where: { userId } });
  if (!credential?.enabledAt) throw forbidden('MFA není aktivní');
  const step = verifyTotp(
    decryptSecret(credential.secretCiphertext),
    code,
    credential.lastUsedStep,
  );
  if (step == null) {
    await failedAttempt(attempt.id);
    throw unauthorized('Neplatný ověřovací kód');
  }
  await prisma.$transaction([
    prisma.userMfaCredential.update({
      where: { userId },
      data: { lastUsedStep: step },
    }),
    prisma.userSession.update({
      where: { id: sessionId },
      data: { mfaVerifiedAt: new Date(), authMethod: 'password_totp' },
    }),
    prisma.authChallenge.update({
      where: { id: attempt.id },
      data: { consumedAt: new Date() },
    }),
  ]);
  await logActivity(userId, 'mfa_step_up', 'user', userId);
  return { ok: true, validForSeconds: config.adminMfa.stepUpMinutes * 60 };
}

export async function regenerateRecoveryCodes(userId: string) {
  const codes = await replaceRecoveryCodes(userId);
  await logActivity(userId, 'mfa_recovery_regenerated', 'user', userId);
  return { recoveryCodes: codes };
}

export async function resetMfa(actorId: string, targetUserId: string) {
  const target = await prisma.user.findUnique({ where: { id: targetUserId } });
  if (!target || target.role !== UserRole.admin) throw badRequest('Admin účet nenalezen');
  await prisma.$transaction([
    prisma.userMfaCredential.deleteMany({ where: { userId: targetUserId } }),
    prisma.mfaRecoveryCode.deleteMany({ where: { userId: targetUserId } }),
    prisma.authChallenge.deleteMany({ where: { userId: targetUserId } }),
    prisma.userSession.deleteMany({ where: { userId: targetUserId } }),
  ]);
  await logActivity(actorId, 'mfa_reset', 'user', targetUserId);
  await sendSecurityAlert('mfa_reset');
}

export async function assertAdminMfaRolloutReady() {
  if (!config.adminMfa.required) return;
  const admins = await prisma.user.findMany({
    where: { role: UserRole.admin, isActive: true },
    select: {
      id: true,
      username: true,
      passwordHash: true,
      mfaCredential: { select: { enabledAt: true } },
      mfaRecoveryCodes: {
        where: { usedAt: null },
        select: { id: true },
      },
    },
  });
  if (admins.length < 2) {
    throw new Error('ADMIN_MFA_REQUIRED needs at least two active admin accounts');
  }
  for (const admin of admins) {
    if (!admin.passwordHash || !admin.mfaCredential?.enabledAt) {
      throw new Error(`Admin ${admin.username} is not ready for mandatory MFA`);
    }
    if (admin.mfaRecoveryCodes.length === 0) {
      throw new Error(`Admin ${admin.username} has no unused MFA recovery code`);
    }
    const recoveryVerified = await prisma.activityLog.findFirst({
      where: { userId: admin.id, action: 'mfa_recovery_used' },
      select: { id: true },
    });
    if (!recoveryVerified) {
      throw new Error(`Admin ${admin.username} has not verified MFA recovery`);
    }
  }
}

export function assertStrongAdminPassword(value: string) {
  const common = new Set([
    'password1234',
    'administrator',
    'admin123456',
    'qwerty123456',
    '123456789012',
  ]);
  if (value.length < 12 || value.length > 128) {
    throw badRequest('Admin heslo musí mít 12 až 128 znaků');
  }
  if (common.has(value.toLowerCase()) || /^\d+$/.test(value)) {
    throw badRequest('Admin heslo je příliš slabé');
  }
}
