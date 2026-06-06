import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';

export async function logActivity(
  userId: string,
  action: string,
  entityType?: string,
  entityId?: string,
  metadata?: Record<string, unknown>,
) {
  await prisma.activityLog.create({
    data: {
      userId,
      action,
      entityType,
      entityId,
      metadata: metadata ? (metadata as Prisma.InputJsonValue) : undefined,
    },
  });
}

export async function logChange(
  userId: string,
  entityType: string,
  entityId: string,
  fieldName: string,
  oldValue: string | null,
  newValue: string | null,
  metadata?: Record<string, unknown>,
) {
  await prisma.changeLog.create({
    data: {
      userId,
      entityType,
      entityId,
      fieldName,
      oldValue,
      newValue,
      metadata: metadata ? (metadata as Prisma.InputJsonValue) : undefined,
    },
  });
}

export async function logError(
  message: string,
  opts?: { stack?: string; path?: string; method?: string; userId?: string; metadata?: Record<string, unknown> },
) {
  await prisma.errorLog.create({
    data: {
      message,
      stack: opts?.stack,
      path: opts?.path,
      method: opts?.method,
      userId: opts?.userId,
      metadata: opts?.metadata ? (opts.metadata as Prisma.InputJsonValue) : undefined,
    },
  });
}

export async function getSealHistory(sealId: string) {
  const [changes, activities] = await Promise.all([
    prisma.changeLog.findMany({
      where: { entityType: 'seal', entityId: sealId },
      include: { user: { select: { id: true, displayName: true, username: true } } },
      orderBy: { createdAt: 'desc' },
    }),
    prisma.activityLog.findMany({
      where: { entityType: 'seal', entityId: sealId },
      include: { user: { select: { id: true, displayName: true, username: true } } },
      orderBy: { createdAt: 'desc' },
    }),
  ]);

  type HistoryEntry = {
    id: string;
    type: 'change' | 'activity';
    timestamp: Date;
    editor: { id: string; displayName: string; username: string };
    action?: string;
    fieldName?: string | null;
    oldValue?: string | null;
    newValue?: string | null;
    metadata?: unknown;
  };

  const entries: HistoryEntry[] = [
    ...changes.map((c) => ({
      id: c.id,
      type: 'change' as const,
      timestamp: c.createdAt,
      editor: c.user,
      fieldName: c.fieldName,
      oldValue: c.oldValue,
      newValue: c.newValue,
      metadata: c.metadata,
    })),
    ...activities.map((a) => ({
      id: a.id,
      type: 'activity' as const,
      timestamp: a.createdAt,
      editor: a.user,
      action: a.action,
      metadata: a.metadata,
    })),
  ];

  entries.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());
  return entries;
}
