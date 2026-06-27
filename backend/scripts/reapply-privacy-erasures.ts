import fs from 'node:fs';
import bcrypt from 'bcrypt';
import { Prisma } from '@prisma/client';
import { prisma } from '../src/lib/prisma.js';

async function main() {
  const path = process.env.PRIVACY_LEDGER_PATH;
  if (!path) throw new Error('PRIVACY_LEDGER_PATH is required');
  const lines = fs.readFileSync(path, 'utf8').split(/\r?\n/).filter(Boolean);
  for (const line of lines) {
    const row = JSON.parse(line) as {
      subject_user_id: string;
      actor_user_id: string;
      original_username_hash: string;
      performed_at: string;
    };
    const user = await prisma.user.findUnique({ where: { id: row.subject_user_id } });
    if (!user) continue;
    const lockedHash = await bcrypt.hash(`restored-erased-${row.subject_user_id}`, 10);
    await prisma.$transaction([
      prisma.loginLog.deleteMany({ where: { userId: user.id } }),
      prisma.userSession.deleteMany({ where: { userId: user.id } }),
      prisma.notification.deleteMany({ where: { userId: user.id } }),
      prisma.privateMessage.deleteMany({
        where: { OR: [{ senderId: user.id }, { recipientId: user.id }] },
      }),
      prisma.errorLog.deleteMany({ where: { userId: user.id } }),
      prisma.syncMutation.deleteMany({ where: { userId: user.id } }),
      prisma.privacyNoticeAcceptance.deleteMany({ where: { userId: user.id } }),
      prisma.userMfaCredential.deleteMany({ where: { userId: user.id } }),
      prisma.mfaRecoveryCode.deleteMany({ where: { userId: user.id } }),
      prisma.authChallenge.deleteMany({ where: { userId: user.id } }),
      prisma.activityLog.updateMany({
        where: { userId: user.id },
        data: { metadata: Prisma.JsonNull },
      }),
      prisma.changeLog.updateMany({
        where: { userId: user.id },
        data: { metadata: Prisma.JsonNull },
      }),
      prisma.user.update({
        where: { id: user.id },
        data: {
          username: `deleted_${user.id}`,
          displayName: 'Smazaný uživatel',
          pinHash: lockedHash,
          passwordHash: null,
          isActive: false,
          mustChangePin: false,
        },
      }),
      prisma.privacyErasure.upsert({
        where: { subjectUserId: user.id },
        update: {
          actorUserId: row.actor_user_id,
          originalUsernameHash: row.original_username_hash,
          performedAt: new Date(row.performed_at),
          details: { restoredReplay: true },
        },
        create: {
          subjectUserId: user.id,
          actorUserId: row.actor_user_id,
          originalUsernameHash: row.original_username_hash,
          performedAt: new Date(row.performed_at),
          details: { restoredReplay: true },
        },
      }),
    ]);
    console.log(`Reapplied privacy erasure for ${user.id}`);
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
