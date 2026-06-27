import { createHmac } from 'node:crypto';
import bcrypt from 'bcrypt';
import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';
import { config } from '../dist/config.js';

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function decodeBase32(input) {
  let bits = 0;
  let value = 0;
  const bytes = [];
  for (const char of input.toUpperCase().replace(/=|\s|-/g, '')) {
    value = (value << 5) | BASE32.indexOf(char);
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

function totp(secret, step = Math.floor(Date.now() / 30000)) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const digest = createHmac('sha1', decodeBase32(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 0xf;
  const value =
    (((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      digest[offset + 3]) %
    1000000;
  return value.toString().padStart(6, '0');
}

describe('P0 admin MFA and privacy controls', () => {
  const app = createApp();
  const adminPassword = 'Correct-Horse-Battery-2026!';
  let adminId;
  let secret;
  let adminToken;
  let recoveryCode;
  let tempUserId;
  const originalMfaRequired = config.adminMfa.required;

  beforeAll(async () => {
    config.adminMfa.required = true;
    const admin = await prisma.user.findUniqueOrThrow({ where: { username: 'admin' } });
    adminId = admin.id;
    await prisma.user.update({
      where: { id: admin.id },
      data: {
        passwordHash: await bcrypt.hash(adminPassword, 10),
        mustChangePin: false,
      },
    });
    await prisma.userMfaCredential.deleteMany({ where: { userId: admin.id } });
    await prisma.mfaRecoveryCode.deleteMany({ where: { userId: admin.id } });
    await prisma.authChallenge.deleteMany({ where: { userId: admin.id } });
  });

  afterAll(async () => {
    config.adminMfa.required = originalMfaRequired;
    await prisma.authChallenge.deleteMany({ where: { userId: adminId } });
    await prisma.mfaRecoveryCode.deleteMany({ where: { userId: adminId } });
    await prisma.userMfaCredential.deleteMany({ where: { userId: adminId } });
    await prisma.userSession.deleteMany({ where: { userId: adminId } });
    await prisma.user.update({
      where: { id: adminId },
      data: { passwordHash: null },
    });
    if (tempUserId) {
      await prisma.privacyErasure.deleteMany({ where: { subjectUserId: tempUserId } });
      await prisma.user.deleteMany({ where: { id: tempUserId } });
    }
    await prisma.$disconnect();
  });

  it('enrolls TOTP and returns one-time recovery codes', async () => {
    const login = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', credential: adminPassword });
    expect(login.status).toBe(200);
    expect(login.body.code).toBe('MFA_ENROLLMENT_REQUIRED');
    expect(login.body.token).toBeUndefined();

    const start = await request(app)
      .post('/api/auth/mfa/enroll/start')
      .send({ challengeToken: login.body.challengeToken });
    expect(start.status).toBe(200);
    secret = start.body.secret;
    expect(start.body.otpauthUri).toContain('otpauth://totp/');

    const confirm = await request(app)
      .post('/api/auth/mfa/enroll/confirm')
      .send({
        challengeToken: login.body.challengeToken,
        code: totp(secret),
      });
    expect(confirm.status).toBe(200);
    expect(confirm.body.recoveryCodes).toHaveLength(10);
    expect(confirm.body.token).toBeTruthy();
    adminToken = confirm.body.token;
    recoveryCode = confirm.body.recoveryCodes[0];

    const stored = await prisma.mfaRecoveryCode.findMany({ where: { userId: adminId } });
    expect(stored).toHaveLength(10);
    expect(stored[0].codeHash).not.toBe(confirm.body.recoveryCodes[0]);
  });

  it('requires MFA challenge on subsequent admin login', async () => {
    const login = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', credential: adminPassword });
    expect(login.status).toBe(200);
    expect(login.body.code).toBe('MFA_REQUIRED');

    // Enrollment used the current step; clear it only to keep the test deterministic.
    await prisma.userMfaCredential.update({
      where: { userId: adminId },
      data: { lastUsedStep: null },
    });
    const verify = await request(app)
      .post('/api/auth/mfa/verify-login')
      .send({ challengeToken: login.body.challengeToken, code: totp(secret) });
    expect(verify.status).toBe(200);
    expect(verify.body.token).toBeTruthy();
  });

  it('rejects an expired challenge and a replayed TOTP step', async () => {
    const expiredLogin = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', credential: adminPassword });
    const latest = await prisma.authChallenge.findFirstOrThrow({
      where: { userId: adminId, consumedAt: null, kind: 'login' },
      orderBy: { createdAt: 'desc' },
    });
    await prisma.authChallenge.update({
      where: { id: latest.id },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    const expiredVerify = await request(app)
      .post('/api/auth/mfa/verify-login')
      .send({ challengeToken: expiredLogin.body.challengeToken, code: totp(secret) });
    expect(expiredVerify.status).toBe(401);
    expect(expiredVerify.body.token).toBeUndefined();

    const replayLogin = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', credential: adminPassword });
    const replay = await request(app)
      .post('/api/auth/mfa/verify-login')
      .send({ challengeToken: replayLogin.body.challengeToken, code: totp(secret) });
    expect(replay.status).toBe(401);
  });

  it('accepts each recovery code only once', async () => {
    const login = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', credential: adminPassword });
    const first = await request(app)
      .post('/api/auth/mfa/recovery')
      .send({ challengeToken: login.body.challengeToken, code: recoveryCode });
    expect(first.status).toBe(200);
    expect(first.body.token).toBeTruthy();

    const secondLogin = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', credential: adminPassword });
    const second = await request(app)
      .post('/api/auth/mfa/recovery')
      .send({ challengeToken: secondLogin.body.challengeToken, code: recoveryCode });
    expect(second.status).toBe(401);
  });

  it('requires and refreshes recent MFA for a sensitive operation', async () => {
    await prisma.userSession.updateMany({
      where: { userId: adminId },
      data: { mfaVerifiedAt: new Date(Date.now() - 16 * 60_000) },
    });
    const blocked = await request(app)
      .get(`/api/users/${adminId}/privacy-export`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(blocked.status).toBe(403);
    expect(blocked.body.code).toBe('STEP_UP_REQUIRED');

    const stepUp = await request(app)
      .post('/api/auth/mfa/step-up')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ code: totp(secret, Math.floor(Date.now() / 30000) + 1) });
    expect(stepUp.status).toBe(200);

    const allowed = await request(app)
      .get(`/api/users/${adminId}/privacy-export`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(allowed.status).toBe(200);
  });

  it('exports privacy data and records anonymization', async () => {
    const pinHash = await bcrypt.hash('987654', 10);
    const temp = await prisma.user.create({
      data: {
        username: `privacy-${Date.now()}`,
        displayName: 'Privacy Test',
        pinHash,
        role: 'worker',
      },
    });
    tempUserId = temp.id;
    await prisma.errorLog.create({
      data: { message: 'test personal error', userId: temp.id },
    });

    const exportRes = await request(app)
      .get(`/api/users/${temp.id}/privacy-export`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(exportRes.status).toBe(200);
    expect(exportRes.body.subject.id).toBe(temp.id);
    expect(exportRes.body.errors).toHaveLength(1);

    const deletion = await request(app)
      .delete(`/api/users/${temp.id}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(deletion.status).toBe(204);

    const erased = await prisma.privacyErasure.findFirst({
      where: { subjectUserId: temp.id },
    });
    expect(erased).toBeTruthy();
    expect(await prisma.errorLog.count({ where: { userId: temp.id } })).toBe(0);
    const anonymized = await prisma.user.findUniqueOrThrow({ where: { id: temp.id } });
    expect(anonymized.username).toBe(`deleted_${temp.id}`);
    expect(anonymized.isActive).toBe(false);
  });
});
