import { z } from 'zod';
import { prisma } from '../lib/prisma.js';

export const backupRunSchema = z.object({
  type: z.enum(['db', 'object', 'restore_test']),
  status: z.enum(['success', 'failed']),
  githubRunUrl: z.string().url().optional().nullable(),
  r2Prefix: z.string().max(500).optional().nullable(),
  manifestKey: z.string().max(500).optional().nullable(),
  bytes: z.union([z.number().int().nonnegative(), z.string().regex(/^\d+$/)]).optional().nullable(),
  objectCount: z.number().int().nonnegative().optional().nullable(),
  errorMessage: z.string().max(4000).optional().nullable(),
  startedAt: z.string().datetime().optional().nullable(),
  finishedAt: z.string().datetime().optional().nullable(),
});

export type BackupRunInput = z.infer<typeof backupRunSchema>;

function bigIntOrNull(value: BackupRunInput['bytes']) {
  if (value === undefined || value === null) return null;
  return BigInt(value);
}

function dateOrNull(value: string | null | undefined) {
  return value ? new Date(value) : null;
}

function serializeBackupRun(row: Awaited<ReturnType<typeof prisma.backupRun.findFirst>>) {
  if (!row) return null;
  return {
    id: row.id,
    type: row.type,
    status: row.status,
    githubRunUrl: row.githubRunUrl,
    r2Prefix: row.r2Prefix,
    manifestKey: row.manifestKey,
    bytes: row.bytes?.toString() ?? null,
    objectCount: row.objectCount,
    errorMessage: row.errorMessage,
    startedAt: row.startedAt,
    finishedAt: row.finishedAt,
    createdAt: row.createdAt,
  };
}

export async function recordBackupRun(input: BackupRunInput) {
  const data = backupRunSchema.parse(input);
  const row = await prisma.backupRun.create({
    data: {
      type: data.type,
      status: data.status,
      githubRunUrl: data.githubRunUrl ?? null,
      r2Prefix: data.r2Prefix ?? null,
      manifestKey: data.manifestKey ?? null,
      bytes: bigIntOrNull(data.bytes),
      objectCount: data.objectCount ?? null,
      errorMessage: data.errorMessage ?? null,
      startedAt: dateOrNull(data.startedAt),
      finishedAt: dateOrNull(data.finishedAt),
    },
  });
  return serializeBackupRun(row);
}

export async function listBackupRuns(limit = 50) {
  const rows = await prisma.backupRun.findMany({
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
  return rows.map((row) => serializeBackupRun(row)!);
}

export async function getBackupStatus() {
  const [db, object, restoreTest] = await Promise.all([
    prisma.backupRun.findFirst({ where: { type: 'db' }, orderBy: { createdAt: 'desc' } }),
    prisma.backupRun.findFirst({ where: { type: 'object' }, orderBy: { createdAt: 'desc' } }),
    prisma.backupRun.findFirst({ where: { type: 'restore_test' }, orderBy: { createdAt: 'desc' } }),
  ]);

  return {
    database: serializeBackupRun(db),
    objects: serializeBackupRun(object),
    restoreTest: serializeBackupRun(restoreTest),
  };
}
