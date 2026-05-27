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
) {
  await prisma.changeLog.create({
    data: {
      userId,
      entityType,
      entityId,
      fieldName,
      oldValue,
      newValue,
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
