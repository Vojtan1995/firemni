import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';
import { markSealChecked } from './helpers/integration-helpers.js';

describe('Auth and role authorization (BE-02)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let adminToken;
  let jobId;
  let floorId;
  let sealId;

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '123456' });
    return res;
  }

  beforeAll(async () => {
    const workerRes = await login('worker1');
    expect(workerRes.status).toBe(200);
    workerToken = workerRes.body.token;

    const mgmtRes = await login('vedeni');
    expect(mgmtRes.status).toBe(200);
    managementToken = mgmtRes.body.token;

    const adminRes = await login('admin');
    expect(adminRes.status).toBe(200);
    adminToken = adminRes.body.token;

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;

    const sealRes = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber: '99001',
        system: 'Test',
        construction: 'Stěna',
        location: 'Chodba',
        fireRating: 'EI 60',
        entries: [
          {
            entryType: 'Kabel',
            dimension: '50',
            quantity: 1,
            insulation: 'Minerál',
            materials: ['Pěna'],
          },
        ],
      });
    expect(sealRes.status).toBe(201);
    sealId = sealRes.body.id;
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({ where: { sealNumber: '99001' } });
    await prisma.user.updateMany({
      where: { username: 'worker2' },
      data: { isActive: true },
    });
    await prisma.$disconnect();
  });

  it('stores hashed session token, not raw JWT', async () => {
    const res = await login('worker1');
    expect(res.status).toBe(200);
    const token = res.body.token;
    const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
    const session = await prisma.userSession.findUnique({ where: { id: payload.sid } });
    expect(session).toBeTruthy();
    expect(session.token).not.toBe(token);
    expect(session.token).toMatch(/^[a-f0-9]{64}$/);
  });

  it('GET /api/jobs without token → 401', async () => {
    const res = await request(app).get('/api/jobs');
    expect(res.status).toBe(401);
    expect(res.body.code).toBe('UNAUTHORIZED');
  });

  it('GET /api/jobs with invalid token → 401', async () => {
    const res = await request(app)
      .get('/api/jobs')
      .set('Authorization', 'Bearer not-a-valid-jwt');
    expect(res.status).toBe(401);
    expect(res.body.code).toBe('UNAUTHORIZED');
  });

  it('worker cannot POST /api/jobs → 403', async () => {
    const res = await request(app)
      .post('/api/jobs')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        projectNumber: '87654321',
        name: 'Zakázaná stavba',
      });
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('FORBIDDEN');
  });

  it('worker cannot POST /api/jobs/:jobId/floors → 403', async () => {
    const res = await request(app)
      .post(`/api/jobs/${jobId}/floors`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ name: 'Nové patro' });
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('FORBIDDEN');
  });

  it('worker cannot PATCH /api/seals/:id/status → 403', async () => {
    const res = await request(app)
      .patch(`/api/seals/${sealId}/status`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ status: 'checked' });
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('FORBIDDEN');
  });

  it('management can GET /api/jobs → 200', async () => {
    const res = await request(app)
      .get('/api/jobs')
      .set('Authorization', `Bearer ${managementToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('admin can GET /api/logs/activity → 200', async () => {
    const res = await request(app)
      .get('/api/logs/activity')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('GET /api/logs/login with invalid since → 400', async () => {
    const res = await request(app)
      .get('/api/logs/login')
      .query({ since: 'neni-datum' })
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(400);
  });

  it('GET /api/logs/login with valid ISO since → 200', async () => {
    const res = await request(app)
      .get('/api/logs/login')
      .query({ since: '2020-01-01T00:00:00.000Z' })
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('management can PATCH /api/seals/:id/status → 200', async () => {
    const res = await markSealChecked(app, managementToken, workerToken, sealId);
    expect(res.status).toBe('checked');
  });

  describe('deactivated user (isActive)', () => {
    let deactivatedToken;

    beforeAll(async () => {
      const before = await login('worker2');
      expect(before.status).toBe(200);
      deactivatedToken = before.body.token;

      await prisma.user.update({
        where: { username: 'worker2' },
        data: { isActive: false },
      });
    });

    it('login of deactivated user → 401', async () => {
      const res = await login('worker2');
      expect(res.status).toBe(401);
      expect(res.body.code).toBe('UNAUTHORIZED');
    });

    it('API request with session after deactivation → 401', async () => {
      const res = await request(app)
        .get('/api/auth/me')
        .set('Authorization', `Bearer ${deactivatedToken}`);
      expect(res.status).toBe(401);
      expect(res.body.code).toBe('UNAUTHORIZED');
    });
  });
});
