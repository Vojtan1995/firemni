import { UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';
import { forbidden, notFound } from '../lib/errors.js';
import { logActivity } from './audit.service.js';

export async function exportUserPersonalData(
  actorRole: UserRole,
  actorId: string,
  userId: string,
) {
  if (actorRole !== UserRole.admin) throw forbidden('Export osobních údajů smí provést pouze admin');
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      username: true,
      displayName: true,
      role: true,
      materialMode: true,
      isActive: true,
      mustChangePin: true,
      createdAt: true,
      updatedAt: true,
    },
  });
  if (!user) throw notFound('Uživatel nenalezen');

  const [
    loginLogs,
    activityLogs,
    changeLogs,
    sealsCreated,
    photos,
    worksheetsCreated,
    worksheetAssignments,
    worksheetItems,
    messagesSent,
    messagesReceived,
    notifications,
    repairs,
    errors,
    syncMutations,
    privacyAcceptances,
  ] = await Promise.all([
    prisma.loginLog.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
    prisma.activityLog.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
    prisma.changeLog.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
    prisma.seal.findMany({
      where: { createdById: userId },
      select: {
        id: true,
        jobId: true,
        floorId: true,
        sealNumber: true,
        status: true,
        createdAt: true,
        updatedAt: true,
      },
    }),
    prisma.sealPhoto.findMany({
      where: { uploadedById: userId },
      select: { id: true, sealId: true, mimeType: true, fileSize: true, createdAt: true },
    }),
    prisma.workSheet.findMany({
      where: { createdById: userId },
      select: { id: true, jobId: true, status: true, audience: true, createdAt: true },
    }),
    prisma.workSheetWorker.findMany({ where: { userId } }),
    prisma.workSheetItem.findMany({
      where: { workerId: userId },
      select: {
        id: true,
        worksheetId: true,
        sealId: true,
        sealNumber: true,
        quantity: true,
        unit: true,
        createdAt: true,
      },
    }),
    prisma.privateMessage.findMany({
      where: { senderId: userId },
      orderBy: { createdAt: 'asc' },
    }),
    prisma.privateMessage.findMany({
      where: { recipientId: userId },
      orderBy: { createdAt: 'asc' },
    }),
    prisma.notification.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
    prisma.sealRepair.findMany({
      where: { createdById: userId },
      select: { id: true, sealId: true, jobId: true, note: true, createdAt: true },
    }),
    prisma.errorLog.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
    prisma.syncMutation.findMany({
      where: { userId },
      select: {
        id: true,
        deviceId: true,
        entityType: true,
        operation: true,
        processedAt: true,
        createdAt: true,
      },
    }),
    prisma.privacyNoticeAcceptance.findMany({ where: { userId } }),
  ]);

  await logActivity(actorId, 'privacy_export', 'user', userId);
  return {
    formatVersion: 1,
    generatedAt: new Date().toISOString(),
    subject: user,
    loginLogs,
    activityLogs,
    changeLogs,
    sealsCreated,
    photos,
    worksheetsCreated,
    worksheetAssignments,
    worksheetItems,
    messagesSent,
    messagesReceived,
    notifications,
    repairs,
    errors,
    syncMutations,
    privacyAcceptances,
  };
}

export async function getPrivacyNotice(userId: string) {
  const acceptance = await prisma.privacyNoticeAcceptance.findUnique({
    where: {
      userId_version: {
        userId,
        version: config.privacyNotice.version,
      },
    },
  });
  return {
    version: config.privacyNotice.version,
    url: config.privacyNotice.url || null,
    accepted: acceptance != null,
    acceptedAt: acceptance?.acceptedAt ?? null,
  };
}

export async function acceptPrivacyNotice(userId: string, version: string) {
  if (version !== config.privacyNotice.version) {
    throw forbidden('Lze potvrdit pouze aktuální verzi informačního dokumentu');
  }
  const acceptance = await prisma.privacyNoticeAcceptance.upsert({
    where: { userId_version: { userId, version } },
    update: {},
    create: { userId, version },
  });
  await logActivity(userId, 'privacy_notice_accepted', 'user', userId, { version });
  return acceptance;
}
