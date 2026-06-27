import bcrypt from 'bcrypt';
import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import { prisma } from '../dist/lib/prisma.js';
import { config } from '../dist/config.js';
import { assertAdminMfaRolloutReady } from '../dist/services/mfa.service.js';

describe('mandatory admin MFA startup gate', () => {
  const originalRequired = config.adminMfa.required;
  const ids = [];

  beforeAll(async () => {
    config.adminMfa.required = true;
    await prisma.user.updateMany({
      where: { role: 'admin' },
      data: { isActive: false },
    });
  });

  afterAll(async () => {
    await prisma.activityLog.deleteMany({ where: { userId: { in: ids } } });
    await prisma.user.deleteMany({ where: { id: { in: ids } } });
    await prisma.user.updateMany({
      where: { username: 'admin' },
      data: { isActive: true },
    });
    config.adminMfa.required = originalRequired;
    await prisma.$disconnect();
  });

  it('rejects fewer than two ready administrators', async () => {
    await expect(assertAdminMfaRolloutReady()).rejects.toThrow('at least two');
  });

  it('accepts two fully enrolled administrators with verified recovery', async () => {
    for (const suffix of ['a', 'b']) {
      const user = await prisma.user.create({
        data: {
          username: `mfa-ready-${suffix}-${Date.now()}`,
          displayName: `MFA Ready ${suffix}`,
          role: 'admin',
          pinHash: await bcrypt.hash(`locked-${suffix}`, 10),
          passwordHash: await bcrypt.hash(`Strong-Admin-${suffix}-2026!`, 10),
          mfaCredential: {
            create: {
              secretCiphertext: 'test-ciphertext-not-decrypted',
              enabledAt: new Date(),
            },
          },
          mfaRecoveryCodes: {
            create: { codeHash: await bcrypt.hash(`RECOVERY-${suffix}`, 10) },
          },
        },
      });
      ids.push(user.id);
      await prisma.activityLog.create({
        data: {
          userId: user.id,
          action: 'mfa_recovery_used',
          entityType: 'user',
          entityId: user.id,
        },
      });
    }
    await expect(assertAdminMfaRolloutReady()).resolves.toBeUndefined();
  });
});
