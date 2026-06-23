import fs from 'fs';
import path from 'path';
import { PrismaClient } from '@prisma/client';

type FileRecord = {
  type: 'photo' | 'drawing';
  id: string;
  filePath: string;
  mimeType: string;
  endpointPath?: string;
};

type ApiResult = {
  checked: number;
  ok: number;
  notFound: number;
  forbidden: number;
  unauthorized: number;
  other: number;
  errors: number;
  samples: Array<{ type: string; id: string; status: number | 'error'; filePath: string }>;
};

const rootDir = path.resolve(process.cwd(), '..');
const defaultEnvFiles = [
  path.resolve(process.cwd(), '.env'),
  path.resolve(process.cwd(), '.env.local'),
  path.resolve(rootDir, '.env.local'),
];

function parseArgs() {
  const args = process.argv.slice(2);
  const command = args.find((arg) => !arg.startsWith('--')) ?? 'audit';
  const flags = new Set(args.filter((arg) => arg.startsWith('--')));
  const envFiles = args
    .filter((arg) => arg.startsWith('--env='))
    .map((arg) => path.resolve(arg.slice('--env='.length)));
  return { command, flags, envFiles };
}

function loadEnvFile(filePath: string) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

function loadEnv(envFiles: string[]) {
  for (const file of [...defaultEnvFiles, ...envFiles]) {
    loadEnvFile(file);
  }
  const r2AccountId = process.env.R2_ACCOUNT_ID ?? process.env.CLOUDFLARE_ACCOUNT_ID;
  if (!process.env.S3_ENDPOINT && r2AccountId) {
    process.env.S3_ENDPOINT = `https://${r2AccountId}.r2.cloudflarestorage.com`;
  }
  if (!process.env.S3_REGION && r2AccountId) {
    process.env.S3_REGION = 'auto';
  }
  if (!process.env.S3_FORCE_PATH_STYLE && r2AccountId) {
    process.env.S3_FORCE_PATH_STYLE = 'true';
  }
  if (process.env.PROD_DATABASE_URL) {
    process.env.DATABASE_URL = process.env.PROD_DATABASE_URL;
  }
  if (process.env.PROD_API_BASE_URL) {
    process.env.API_BASE_URL = process.env.PROD_API_BASE_URL;
  }
  if (process.env.PROD_API_TOKEN) {
    process.env.API_TOKEN = process.env.PROD_API_TOKEN;
  }
}

function requireEnv(names: string[]) {
  const missing = names.filter((name) => !process.env[name]);
  if (missing.length > 0) {
    throw new Error(`Missing required env: ${missing.join(', ')}`);
  }
}

function publicEnvSummary() {
  return {
    storageDriver: process.env.STORAGE_DRIVER ?? 'local',
    publicUploads: process.env.PUBLIC_UPLOADS,
    s3Endpoint: process.env.S3_ENDPOINT ? '<set>' : '<missing>',
    s3Bucket: process.env.S3_BUCKET ? '<set>' : '<missing>',
    s3KeyPrefix: process.env.S3_KEY_PREFIX ?? 'photos',
    r2AccountId: process.env.R2_ACCOUNT_ID || process.env.CLOUDFLARE_ACCOUNT_ID ? '<set>' : '<missing>',
    databaseUrl: process.env.DATABASE_URL ? '<set>' : '<missing>',
    apiBaseUrl: process.env.API_BASE_URL ? '<set>' : '<missing>',
    apiToken: process.env.API_TOKEN ? '<set>' : '<missing>',
  };
}

async function mapLimit<T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>,
) {
  const results: R[] = [];
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < items.length) {
      const current = nextIndex;
      nextIndex += 1;
      results[current] = await fn(items[current]);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, () => worker()),
  );
  return results;
}

async function loadRecords(prisma: PrismaClient): Promise<FileRecord[]> {
  const photos = await prisma.sealPhoto.findMany({
    select: {
      id: true,
      filePath: true,
      mimeType: true,
    },
    orderBy: { createdAt: 'asc' },
  });

  const drawings = await prisma.floorDrawing.findMany({
    select: {
      id: true,
      floorId: true,
      filePath: true,
      mimeType: true,
      floor: { select: { jobId: true } },
    },
    orderBy: { updatedAt: 'asc' },
  });

  return [
    ...photos.map((photo) => ({
      type: 'photo' as const,
      id: photo.id,
      filePath: photo.filePath,
      mimeType: photo.mimeType,
      endpointPath: `/api/photos/${photo.id}/file`,
    })),
    ...drawings.map((drawing) => ({
      type: 'drawing' as const,
      id: drawing.id,
      filePath: drawing.filePath,
      mimeType: drawing.mimeType,
      endpointPath: `/api/jobs/${drawing.floor.jobId}/floors/${drawing.floorId}/drawing/file`,
    })),
  ];
}

async function auditApi(records: FileRecord[]): Promise<ApiResult | null> {
  const baseUrl = process.env.API_BASE_URL?.replace(/\/+$/g, '');
  const token = process.env.API_TOKEN;
  if (!baseUrl || !token) return null;

  const result: ApiResult = {
    checked: 0,
    ok: 0,
    notFound: 0,
    forbidden: 0,
    unauthorized: 0,
    other: 0,
    errors: 0,
    samples: [],
  };

  await mapLimit(records, 4, async (record) => {
    if (!record.endpointPath) return;
    try {
      const response = await fetch(`${baseUrl}${record.endpointPath}`, {
        method: 'GET',
        headers: { Authorization: `Bearer ${token}` },
      });
      result.checked += 1;
      if (response.status === 200) result.ok += 1;
      else if (response.status === 404) result.notFound += 1;
      else if (response.status === 403) result.forbidden += 1;
      else if (response.status === 401) result.unauthorized += 1;
      else result.other += 1;

      if (response.status !== 200 && result.samples.length < 20) {
        result.samples.push({
          type: record.type,
          id: record.id,
          status: response.status,
          filePath: record.filePath,
        });
      }
      await response.body?.cancel();
    } catch {
      result.checked += 1;
      result.errors += 1;
      if (result.samples.length < 20) {
        result.samples.push({
          type: record.type,
          id: record.id,
          status: 'error',
          filePath: record.filePath,
        });
      }
    }
  });

  return result;
}

async function auditStorage() {
  requireEnv(['DATABASE_URL']);
  const { getObjectStorage } = await import('../src/services/storage.service.js');
  const prisma = new PrismaClient();
  try {
    const storage = getObjectStorage();
    const records = await loadRecords(prisma);
    const checks = await mapLimit(records, 8, async (record) => ({
      record,
      exists: await storage.exists(record.filePath),
    }));
    const missing = checks.filter((check) => !check.exists).map((check) => check.record);
    const missingPhotos = missing.filter((record) => record.type === 'photo');
    const missingDrawings = missing.filter((record) => record.type === 'drawing');
    const api = await auditApi(records);

    console.log(
      JSON.stringify(
        {
          generatedAt: new Date().toISOString(),
          env: publicEnvSummary(),
          db: {
            sealPhotos: records.filter((record) => record.type === 'photo').length,
            floorDrawings: records.filter((record) => record.type === 'drawing').length,
          },
          storage: {
            checked: records.length,
            missingTotal: missing.length,
            missingSealPhotos: missingPhotos.length,
            missingFloorDrawings: missingDrawings.length,
            missingSamples: missing.slice(0, 20),
          },
          api,
        },
        null,
        2,
      ),
    );
  } finally {
    await prisma.$disconnect();
  }
}

async function verifyS3() {
  requireEnv([
    'S3_BUCKET',
    'S3_ACCESS_KEY_ID',
    'S3_SECRET_ACCESS_KEY',
    'S3_ENDPOINT',
  ]);
  if ((process.env.STORAGE_DRIVER ?? '').toLowerCase() !== 's3') {
    throw new Error('STORAGE_DRIVER must be s3 for storage verification');
  }

  const { verifyObjectStorageAccess } = await import('../src/services/storage.service.js');
  await verifyObjectStorageAccess();

  console.log(
    JSON.stringify(
      {
        ok: true,
        generatedAt: new Date().toISOString(),
        env: publicEnvSummary(),
      },
      null,
      2,
    ),
  );
}

function printRailwayEnv() {
  const endpoint =
    process.env.S3_ENDPOINT ||
    (process.env.R2_ACCOUNT_ID
      ? `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`
      : process.env.CLOUDFLARE_ACCOUNT_ID
        ? `https://${process.env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`
        : '');
  const values: Record<string, string | undefined> = {
    STORAGE_DRIVER: 's3',
    PUBLIC_UPLOADS: 'false',
    S3_BUCKET: process.env.S3_BUCKET,
    S3_ACCESS_KEY_ID: process.env.S3_ACCESS_KEY_ID,
    S3_SECRET_ACCESS_KEY: process.env.S3_SECRET_ACCESS_KEY,
    S3_ENDPOINT: endpoint,
    S3_REGION: process.env.S3_REGION || 'auto',
    S3_FORCE_PATH_STYLE: process.env.S3_FORCE_PATH_STYLE || 'true',
    S3_KEY_PREFIX: process.env.S3_KEY_PREFIX || 'photos',
  };
  const missing = Object.entries(values)
    .filter(([, value]) => !value)
    .map(([key]) => key);
  if (missing.length > 0) {
    throw new Error(`Missing env for Railway block: ${missing.join(', ')}`);
  }

  for (const [key, value] of Object.entries(values)) {
    console.log(`${key}=${value}`);
  }
}

async function backfillLocal(write: boolean) {
  requireEnv(['DATABASE_URL']);
  if ((process.env.STORAGE_DRIVER ?? '').toLowerCase() !== 's3') {
    throw new Error('STORAGE_DRIVER must be s3 for local backfill');
  }

  const localUploadPath = path.resolve(
    process.env.LOCAL_UPLOAD_PATH ?? path.resolve(process.cwd(), 'uploads'),
  );
  const { getObjectStorage } = await import('../src/services/storage.service.js');
  const prisma = new PrismaClient();
  try {
    const storage = getObjectStorage();
    const records = await loadRecords(prisma);
    const report = {
      write,
      localUploadPath,
      checked: records.length,
      alreadyInStorage: 0,
      localMissing: 0,
      wouldUpload: 0,
      uploaded: 0,
      failed: 0,
      samples: [] as Array<{ type: string; id: string; filePath: string; action: string }>,
    };

    for (const record of records) {
      if (await storage.exists(record.filePath)) {
        report.alreadyInStorage += 1;
        continue;
      }

      const localFile = path.join(localUploadPath, path.basename(record.filePath));
      if (!fs.existsSync(localFile)) {
        report.localMissing += 1;
        if (report.samples.length < 20) {
          report.samples.push({
            type: record.type,
            id: record.id,
            filePath: record.filePath,
            action: 'local-missing',
          });
        }
        continue;
      }

      if (!write) {
        report.wouldUpload += 1;
        if (report.samples.length < 20) {
          report.samples.push({
            type: record.type,
            id: record.id,
            filePath: record.filePath,
            action: 'would-upload',
          });
        }
        continue;
      }

      try {
        await storage.put(record.filePath, fs.readFileSync(localFile), record.mimeType);
        report.uploaded += 1;
      } catch {
        report.failed += 1;
        if (report.samples.length < 20) {
          report.samples.push({
            type: record.type,
            id: record.id,
            filePath: record.filePath,
            action: 'upload-failed',
          });
        }
      }
    }

    console.log(JSON.stringify(report, null, 2));
  } finally {
    await prisma.$disconnect();
  }
}

async function main() {
  const { command, flags, envFiles } = parseArgs();
  loadEnv(envFiles);

  if (flags.has('--help')) {
    console.log(`Usage:
  npm run storage:verify -- [--env=../.env.local]
  npm run storage:audit -- [--env=../.env.local]
  npm run storage:backfill-local -- [--env=../.env.local] [--write]
  npm run storage:railway-env -- [--env=../.env.local]

Env aliases:
  PROD_DATABASE_URL -> DATABASE_URL
  PROD_API_BASE_URL -> API_BASE_URL
  PROD_API_TOKEN    -> API_TOKEN
  R2_ACCOUNT_ID     -> S3_ENDPOINT=https://<id>.r2.cloudflarestorage.com
  CLOUDFLARE_ACCOUNT_ID -> S3_ENDPOINT=https://<id>.r2.cloudflarestorage.com
`);
    return;
  }

  if (command === 'verify') {
    await verifyS3();
  } else if (command === 'audit') {
    await auditStorage();
  } else if (command === 'railway-env') {
    printRailwayEnv();
  } else if (command === 'backfill-local') {
    await backfillLocal(flags.has('--write'));
  } else {
    throw new Error(`Unknown command: ${command}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
