import { describe, it, expect, beforeAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { config } from '../dist/config.js';
import { prisma } from '../dist/lib/prisma.js';

describe('Admin backup API', () => {
  const app = createApp();
  let adminToken;
  let workerToken;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    config.backup.reportToken = 'test-backup-token';
    adminToken = await login('admin');
    workerToken = await login('worker1');
  });

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

  it('admin can trigger backup (success or logged failure)', async () => {
    const res = await request(app)
      .post('/api/admin/backup')
      .set('Authorization', `Bearer ${adminToken}`);
    expect([201, 500]).toContain(res.status);
    expect(res.body.status).toBeDefined();
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
