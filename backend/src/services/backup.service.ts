import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { config } from '../config.js';
import { prisma } from '../lib/prisma.js';
import { logger } from '../lib/logger.js';

const execFileAsync = promisify(execFile);

function timestampSlug() {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}_${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
}

async function ensureBackupDir() {
  await fs.mkdir(path.resolve(config.backup.dir), { recursive: true });
}

async function runPgDump(filePath: string) {
  if (!config.databaseUrl) {
    throw new Error('DATABASE_URL není nastavena');
  }
  await execFileAsync('pg_dump', [config.databaseUrl, '-Fc', '-f', filePath], {
    env: process.env,
  });
}

export async function pruneOldBackups() {
  const retention = Math.max(1, config.backup.retentionCount);
  const rows = await prisma.backupLog.findMany({
    where: { status: 'success' },
    orderBy: { createdAt: 'desc' },
    skip: retention,
    select: { id: true, filePath: true },
  });
  for (const row of rows) {
    try {
      await fs.unlink(path.resolve(row.filePath));
    } catch (_) {}
    await prisma.backupLog.delete({ where: { id: row.id } });
  }
}

const LOG_RETENTION_DAYS = 90;

/**
 * Promaže staré technické logy (přihlášení, chyby, zpracované sync mutace).
 * Audit (ActivityLog / ChangeLog) se záměrně NEMAŽE – je to trvalá historie.
 */
export async function pruneOldLogs() {
  const cutoff = new Date(Date.now() - LOG_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  await prisma.loginLog.deleteMany({ where: { createdAt: { lt: cutoff } } });
  await prisma.errorLog.deleteMany({ where: { createdAt: { lt: cutoff } } });
  await prisma.syncMutation.deleteMany({
    where: { createdAt: { lt: cutoff }, processedAt: { not: null } },
  });
}

export async function runBackup(triggeredBy?: string) {
  await ensureBackupDir();
  const fileName = `ucpavky_${timestampSlug()}.dump`;
  const filePath = path.resolve(config.backup.dir, fileName);

  try {
    await runPgDump(filePath);
    const stat = await fs.stat(filePath);
    const log = await prisma.backupLog.create({
      data: {
        fileName,
        filePath,
        fileSizeBytes: BigInt(stat.size),
        status: 'success',
        triggeredBy: triggeredBy ?? 'manual',
      },
    });
    await pruneOldBackups();
    try {
      await pruneOldLogs();
    } catch (err) {
      logger.warn({ err: String(err) }, 'pruneOldLogs failed');
    }
    logger.info({ fileName, size: stat.size }, 'DB backup OK');
    return log;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    try {
      await fs.unlink(filePath);
    } catch (_) {}
    const log = await prisma.backupLog.create({
      data: {
        fileName,
        filePath,
        status: 'failed',
        errorMessage: message,
        triggeredBy: triggeredBy ?? 'manual',
      },
    });
    logger.error({ err: message }, 'DB backup failed');
    return log;
  }
}

export async function listBackupLogs(limit = 50) {
  const rows = await prisma.backupLog.findMany({
    orderBy: { createdAt: 'desc' },
    take: limit,
  });
  return rows.map((r: (typeof rows)[number]) => ({
    id: r.id,
    fileName: r.fileName,
    filePath: r.filePath,
    fileSizeBytes: r.fileSizeBytes?.toString() ?? null,
    status: r.status,
    errorMessage: r.errorMessage,
    triggeredBy: r.triggeredBy,
    createdAt: r.createdAt,
  }));
}

let backupTimer: NodeJS.Timeout | null = null;

export function startBackupScheduler() {
  if (!config.backup.enabled || config.nodeEnv === 'test') return;
  const intervalMs = Math.max(1, config.backup.intervalHours) * 60 * 60 * 1000;
  if (backupTimer) clearInterval(backupTimer);
  backupTimer = setInterval(() => {
    void runBackup('scheduler');
  }, intervalMs);
  logger.info(
    { intervalHours: config.backup.intervalHours, dir: config.backup.dir },
    'Backup scheduler started',
  );
}

export function stopBackupScheduler() {
  if (backupTimer) clearInterval(backupTimer);
  backupTimer = null;
}
