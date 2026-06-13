import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('API smoke (integration)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;

  beforeAll(async () => {
    const workerLogin = await request(app)
      .post('/api/auth/login')
      .send({ username: 'worker1', pin: '123456' });
    expect(workerLogin.status).toBe(200);
    workerToken = workerLogin.body.token;

    const mgmtLogin = await request(app)
      .post('/api/auth/login')
      .send({ username: 'vedeni', pin: '123456' });
    expect(mgmtLogin.status).toBe(200);
    managementToken = mgmtLogin.body.token;
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('GET /health → 200 ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.timestamp).toBeDefined();
  });

  it('GET /ready -> 200 ready with database check', async () => {
    const res = await request(app).get('/ready');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ready');
    expect(res.body.database).toBe('ok');
    expect(res.body.timestamp).toBeDefined();
  });

  it('POST /api/auth/login → token + role', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username: 'worker1', pin: '123456' });
    expect(res.status).toBe(200);
    expect(res.body.token).toEqual(expect.any(String));
    expect(res.body.user.username).toBe('worker1');
    expect(res.body.user.role).toBe('worker');
  });

  it('GET /api/jobs → 200 (management)', async () => {
    const res = await request(app)
      .get('/api/jobs')
      .set('Authorization', `Bearer ${managementToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    const job = res.body.find((j) => j.projectNumber === '12345678');
    expect(job).toBeDefined();
  });

  it('GET /api/jobs/by-number/12345678 → job + floors', async () => {
    const res = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.projectNumber).toBe('12345678');
    expect(Array.isArray(res.body.floors)).toBe(true);
    expect(res.body.floors.length).toBeGreaterThanOrEqual(1);
    jobId = res.body.id;
  });

  it('GET /api/jobs/:jobId/floors → floors list', async () => {
    expect(jobId).toBeDefined();
    const res = await request(app)
      .get(`/api/jobs/${jobId}/floors`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThanOrEqual(1);
    expect(res.body[0]).toHaveProperty('name');
  });
});
