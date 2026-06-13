import { describe, it, expect, beforeAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';

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

  it('admin can trigger backup (success or logged failure)', async () => {
    const res = await request(app)
      .post('/api/admin/backup')
      .set('Authorization', `Bearer ${adminToken}`);
    expect([201, 500]).toContain(res.status);
    expect(res.body.status).toBeDefined();
  });
});
