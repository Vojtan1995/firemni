import { UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';

export type CreateNotificationInput = {
  userId: string;
  type: string;
  title: string;
  body: string;
  entityType?: string;
  entityId?: string;
};

export async function createNotification(input: CreateNotificationInput) {
  return prisma.notification.create({ data: input });
}

export async function notifyUsersByRoles(
  roles: UserRole[],
  input: Omit<CreateNotificationInput, 'userId'>,
) {
  const users = await prisma.user.findMany({
    where: { role: { in: roles }, isActive: true },
    select: { id: true },
  });
  await Promise.all(users.map((u) => createNotification({ ...input, userId: u.id })));
}

export async function listNotifications(userId: string, limit = 50) {
  return prisma.notification.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
}

export async function unreadNotificationCount(userId: string) {
  return prisma.notification.count({
    where: { userId, readAt: null },
  });
}

export async function markNotificationRead(userId: string, notificationId: string) {
  const row = await prisma.notification.findFirst({
    where: { id: notificationId, userId },
  });
  if (!row) return null;
  return prisma.notification.update({
    where: { id: notificationId },
    data: { readAt: new Date() },
  });
}

export async function markAllNotificationsRead(userId: string) {
  await prisma.notification.updateMany({
    where: { userId, readAt: null },
    data: { readAt: new Date() },
  });
}
