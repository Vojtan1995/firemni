import { describe, it, expect, beforeAll, afterEach } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { config } from '../dist/config.js';
import { prisma } from '../dist/lib/prisma.js';

describe('Admin backup API', () => {
  const app = createApp();
  let adminToken;
  let workerToken;
  const createdRunIds = [];

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    config.backup.reportToken = 'test-backup-token';
    config.backup.healthToken = 'test-health-token';
    adminToken = await login('admin');
    workerToken = await login('worker1');
  });

  afterEach(async () => {
    if (createdRunIds.length > 0) {
      await prisma.backupRun.deleteMany({ where: { id: { in: createdRunIds.splice(0) } } });
    }
  });

  async function resetBackupRuns() {
    await prisma.backupRun.deleteMany({});
  }

  async function createBackupRun(data) {
    const row = await prisma.backupRun.create({ data });
    createdRunIds.push(row.id);
    return row;
  }

  function hoursAgo(hours) {
    return new Date(Date.now() - hours * 60 * 60 * 1000);
  }

  it('worker cannot list backups', async () => {
    const res = await request(app)
      .get('/api/admin/backups')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('admin can list backups', async () => {
    const res = await request(app)
      .get('/api/admin/backups')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('internal backup report endpoint requires token and records a run', async () => {
    const denied = await request(app)
      .post('/api/internal/backup-runs')
      .send({ type: 'db', status: 'success' });
    expect(denied.status).toBe(403);

    const res = await request(app)
      .post('/api/internal/backup-runs')
      .set('Authorization', 'Bearer test-backup-token')
      .send({
        type: 'db',
        status: 'success',
        githubRunUrl: 'https://github.com/example/repo/actions/runs/1',
        r2Prefix: 'backups/ucpavky_20260629_020000',
        manifestKey: 'backups/ucpavky_20260629_020000/ucpavky_20260629_020000.manifest.json',
        bytes: '2048',
        finishedAt: new Date().toISOString(),
      });
    expect(res.status).toBe(201);
    expect(res.body.type).toBe('db');
    expect(res.body.status).toBe('success');
    expect(res.body.bytes).toBe('2048');

    const status = await request(app)
      .get('/api/admin/backup-status')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(status.status).toBe(200);
    expect(status.body.status.database.status).toBe('success');

    const logs = await request(app)
      .get('/api/logs/backups')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(logs.status).toBe(200);
    expect(logs.body.some((row) => row.title.includes('DB'))).toBe(true);

    await prisma.backupRun.delete({ where: { id: res.body.id } });
  });

  it('backup health is unhealthy when production runs are missing', async () => {
    await resetBackupRuns();

    const res = await request(app)
      .get('/api/internal/backup-health')
      .set('Authorization', 'Bearer test-health-token');
    expect(res.status).toBe(503);
    expect(res.body.ok).toBe(false);
    expect(res.body.checks.every((check) => check.status === 'missing')).toBe(true);
  });

  it('backup health is healthy when DB, object and restore runs are fresh', async () => {
    await resetBackupRuns();
    const finishedAt = hoursAgo(1);
    await createBackupRun({
      type: 'db',
      status: 'success',
      githubRunUrl: 'https://github.com/example/repo/actions/runs/backup-health-db',
      r2Prefix: 'backups/ucpavky_20260629_020000',
      manifestKey: 'backups/ucpavky_20260629_020000/ucpavky_20260629_020000.manifest.json',
      bytes: BigInt(2048),
      finishedAt,
      createdAt: finishedAt,
    });
    await createBackupRun({
      type: 'object',
      status: 'success',
      githubRunUrl: 'https://github.com/example/repo/actions/runs/backup-health-object',
      r2Prefix: 'objects/2026-06-29_023000',
      manifestKey: 'objects/2026-06-29_023000/object-manifest.sha256',
      bytes: BigInt(4096),
      objectCount: 12,
      finishedAt,
      createdAt: finishedAt,
    });
    await createBackupRun({
      type: 'restore_test',
      status: 'success',
      githubRunUrl: 'https://github.com/example/repo/actions/runs/backup-health-restore',
      r2Prefix: 'backups/ucpavky_20260629_020000',
      finishedAt,
      createdAt: finishedAt,
    });

    const health = await request(app)
      .get('/api/internal/backup-health')
      .set('Authorization', 'Bearer test-health-token');
    expect(health.status).toBe(200);
    expect(health.body.ok).toBe(true);
    expect(health.body.checks.every((check) => check.status === 'ok')).toBe(true);

    const status = await request(app)
      .get('/api/admin/backup-status')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(status.status).toBe(200);
    expect(status.body.ok).toBe(true);
    expect(status.body.checkedAt).toBeDefined();
    expect(status.body.checks).toHaveLength(3);
    expect(status.body.status.database.status).toBe('success');
    expect(Array.isArray(status.body.runs)).toBe(true);
  });

  it('backup health is unhealthy when the latest success is stale', async () => {
    await resetBackupRuns();
    const stale = hoursAgo(31);
    const recentRestore = hoursAgo(2);
    await createBackupRun({
      type: 'db',
      status: 'success',
      finishedAt: stale,
      createdAt: stale,
    });
    await createBackupRun({
      type: 'object',
      status: 'success',
      finishedAt: stale,
      createdAt: stale,
    });
    await createBackupRun({
      type: 'restore_test',
      status: 'success',
      finishedAt: recentRestore,
      createdAt: recentRestore,
    });

    const res = await request(app)
      .get('/api/internal/backup-health')
      .set('Authorization', 'Bearer test-health-token');
    expect(res.status).toBe(503);
    expect(res.body.ok).toBe(false);
    expect(res.body.checks.find((check) => check.type === 'db').status).toBe('stale');
    expect(res.body.checks.find((check) => check.type === 'object').status).toBe('stale');
  });

  it('backup health is unhealthy when the latest run failed after a success', async () => {
    await resetBackupRuns();
    const successAt = hoursAgo(1);
    await createBackupRun({ type: 'db', status: 'success', finishedAt: successAt, createdAt: successAt });
    await createBackupRun({ type: 'object', status: 'success', finishedAt: successAt, createdAt: successAt });
    await createBackupRun({ type: 'restore_test', status: 'success', finishedAt: successAt, createdAt: successAt });
    await createBackupRun({
      type: 'db',
      status: 'failed',
      errorMessage: 'pg_dump failed',
      finishedAt: new Date(),
      createdAt: new Date(),
    });

    const res = await request(app)
      .get('/api/internal/backup-health')
      .set('Authorization', 'Bearer test-health-token');
    expect(res.status).toBe(503);
    expect(res.body.ok).toBe(false);
    expect(res.body.checks.find((check) => check.type === 'db').status).toBe('failed');
    expect(res.body.checks.find((check) => check.type === 'db').errorMessage).toBe('pg_dump failed');
  });

  it('backup health endpoint requires token', async () => {
    const denied = await request(app).get('/api/internal/backup-health');
    expect(denied.status).toBe(403);
  });

  it('admin can trigger backup (success or logged failure)', async () => {
    const res = await request(app)
      .post('/api/admin/backup')
      .set('Authorization', `Bearer ${adminToken}`);
    expect([201, 500]).toContain(res.status);
    expect(res.body.status).toBeDefined();
    if (res.status === 500) {
      expect(res.body.errorMessage).toMatch(/PG_DUMP_NOT_AVAILABLE|BACKUP_FAILED/);
    }
  });

  it('worker cannot verify storage', async () => {
    const res = await request(app)
      .post('/api/admin/storage/verify')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('admin can verify storage access', async () => {
    const res = await request(app)
      .post('/api/admin/storage/verify')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.storage.driver).toBeDefined();
    expect(typeof res.body.storage.publicUploads).toBe('boolean');
    expect(res.body.checkedAt).toBeDefined();
  });
});
