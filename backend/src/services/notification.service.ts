import { JobStatus, UserRole } from "@prisma/client";
import { prisma } from "../lib/prisma.js";

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
  input: Omit<CreateNotificationInput, "userId">,
) {
  const users = await prisma.user.findMany({
    where: { role: { in: roles }, isActive: true },
    select: { id: true },
  });
  await Promise.all(
    users.map((u) => createNotification({ ...input, userId: u.id })),
  );
}

type NotificationRow = Awaited<
  ReturnType<typeof prisma.notification.findMany>
>[number];

async function filterActiveJobNotifications(rows: NotificationRow[]) {
  const sealIds = rows
    .filter((n) => n.entityType === "seal" && n.entityId)
    .map((n) => n.entityId!);
  const worksheetIds = rows
    .filter((n) => n.entityType === "worksheet" && n.entityId)
    .map((n) => n.entityId!);
  const jobIds = rows
    .filter((n) => n.entityType === "job" && n.entityId)
    .map((n) => n.entityId!);

  const [visibleSeals, visibleWorksheets, visibleJobs] = await Promise.all([
    sealIds.length
      ? prisma.seal.findMany({
          where: {
            id: { in: sealIds },
            deletedAt: null,
            job: { deletedAt: null, status: JobStatus.active },
          },
          select: { id: true },
        })
      : [],
    worksheetIds.length
      ? prisma.workSheet.findMany({
          where: {
            id: { in: worksheetIds },
            job: { deletedAt: null, status: JobStatus.active },
          },
          select: { id: true },
        })
      : [],
    jobIds.length
      ? prisma.job.findMany({
          where: {
            id: { in: jobIds },
            deletedAt: null,
            status: JobStatus.active,
          },
          select: { id: true },
        })
      : [],
  ]);

  const visibleSealIds = new Set(visibleSeals.map((s) => s.id));
  const visibleWorksheetIds = new Set(visibleWorksheets.map((w) => w.id));
  const visibleJobIds = new Set(visibleJobs.map((j) => j.id));

  return rows.filter((n) => {
    if (!n.entityType || !n.entityId) return true;
    if (n.entityType === "seal") return visibleSealIds.has(n.entityId);
    if (n.entityType === "worksheet")
      return visibleWorksheetIds.has(n.entityId);
    if (n.entityType === "job") return visibleJobIds.has(n.entityId);
    return true;
  });
}

export async function listNotifications(userId: string, limit = 50) {
  const rows = await prisma.notification.findMany({
    where: { userId },
    orderBy: { createdAt: "desc" },
    take: Math.max(limit * 4, limit),
  });
  return (await filterActiveJobNotifications(rows)).slice(0, limit);
}

export async function unreadNotificationCount(userId: string) {
  const unread = await prisma.notification.findMany({
    where: { userId, readAt: null },
    orderBy: { createdAt: "desc" },
    take: 500,
  });
  return (await filterActiveJobNotifications(unread)).length;
}

export async function markNotificationRead(
  userId: string,
  notificationId: string,
) {
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
