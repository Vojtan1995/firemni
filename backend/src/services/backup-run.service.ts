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
export type BackupRunType = BackupRunInput['type'];
export type BackupHealthStatus = 'ok' | 'missing' | 'failed' | 'stale';

const BACKUP_HEALTH_RULES: Array<{
  type: BackupRunType;
  label: string;
  maxAgeHours: number;
}> = [
  { type: 'db', label: 'DB záloha', maxAgeHours: 30 },
  { type: 'object', label: 'Záloha fotek/výkresů', maxAgeHours: 30 },
  { type: 'restore_test', label: 'Restore test', maxAgeHours: 8 * 24 },
];

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

function runTimestamp(row: NonNullable<Awaited<ReturnType<typeof prisma.backupRun.findFirst>>>) {
  return row.finishedAt ?? row.createdAt;
}

function ageHours(timestamp: Date, now: Date) {
  return Math.max(0, (now.getTime() - timestamp.getTime()) / (60 * 60 * 1000));
}

function backupHealthMessage(
  status: BackupHealthStatus,
  label: string,
  maxAgeHours: number,
) {
  switch (status) {
    case 'ok':
      return `${label} je v limitu`;
    case 'failed':
      return `${label} má poslední běh selhaný`;
    case 'stale':
      return `${label} je starší než ${maxAgeHours} hodin`;
    case 'missing':
    default:
      return `${label} chybí`;
  }
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

export async function getBackupHealth(now = new Date()) {
  const checks = await Promise.all(
    BACKUP_HEALTH_RULES.map(async (rule) => {
      const [latestRun, latestSuccess] = await Promise.all([
        prisma.backupRun.findFirst({
          where: { type: rule.type },
          orderBy: { createdAt: 'desc' },
        }),
        prisma.backupRun.findFirst({
          where: { type: rule.type, status: 'success' },
          orderBy: { createdAt: 'desc' },
        }),
      ]);

      let status: BackupHealthStatus = 'ok';
      const latestSuccessAgeHours = latestSuccess
        ? ageHours(runTimestamp(latestSuccess), now)
        : null;
      if (latestRun?.status === 'failed') {
        status = 'failed';
      } else if (!latestSuccess) {
        status = 'missing';
      } else {
        if (latestSuccessAgeHours !== null && latestSuccessAgeHours > rule.maxAgeHours) {
          status = 'stale';
        }
      }

      return {
        type: rule.type,
        label: rule.label,
        ok: status === 'ok',
        status,
        maxAgeHours: rule.maxAgeHours,
        latestSuccessAgeHours,
        latestRun: serializeBackupRun(latestRun),
        latestSuccess: serializeBackupRun(latestSuccess),
        githubRunUrl: latestRun?.githubRunUrl ?? latestSuccess?.githubRunUrl ?? null,
        r2Prefix: latestRun?.r2Prefix ?? latestSuccess?.r2Prefix ?? null,
        manifestKey: latestRun?.manifestKey ?? latestSuccess?.manifestKey ?? null,
        bytes: (latestRun?.bytes ?? latestSuccess?.bytes)?.toString() ?? null,
        objectCount: latestRun?.objectCount ?? latestSuccess?.objectCount ?? null,
        errorMessage: latestRun?.status === 'failed' ? latestRun.errorMessage : null,
        message: backupHealthMessage(status, rule.label, rule.maxAgeHours),
      };
    }),
  );

  return {
    ok: checks.every((check) => check.ok),
    checkedAt: now.toISOString(),
    checks,
  };
}
