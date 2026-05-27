import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const SEAL_PREFIX = '9905';

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    system: 'Report test',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'Kabel',
        dimension: '50',
        quantity: 2,
        insulation: 'Minerál',
        materials: ['Pěna', 'Malta'],
      },
    ],
  };
}

describe('Reports and exports (BE-05)', () => {
  const app = createApp();
  let worker1Token;
  let worker2Token;
  let managementToken;
  let adminToken;
  let worker1Id;
  let worker2Id;
  let jobId;
  let floor1Id;
  let floor2Id;
  let sealWorker1Floor1;
  let sealWorker2Floor1;
  let sealWorker1Floor2;

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '1234' });
    expect(res.status).toBe(200);
    return res.body;
  }

  async function createSeal(token, body) {
    return request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send(body);
  }

  beforeAll(async () => {
    const w1 = await login('worker1');
    worker1Token = w1.token;
    worker1Id = w1.user.id;

    const w2 = await login('worker2');
    worker2Token = w2.token;
    worker2Id = w2.user.id;

    managementToken = (await login('vedeni')).token;
    adminToken = (await login('admin')).token;

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${worker1Token}`);
    jobId = jobRes.body.id;
    floor1Id = jobRes.body.floors[0].id;
    floor2Id = jobRes.body.floors[1].id;

    const s1 = await createSeal(
      worker1Token,
      sealBody(jobId, floor1Id, `${SEAL_PREFIX}1`),
    );
    expect(s1.status).toBe(201);
    sealWorker1Floor1 = s1.body.id;

    const s2 = await createSeal(
      worker2Token,
      sealBody(jobId, floor1Id, `${SEAL_PREFIX}2`),
    );
    expect(s2.status).toBe(201);
    sealWorker2Floor1 = s2.body.id;

    const s3 = await createSeal(
      worker1Token,
      sealBody(jobId, floor2Id, `${SEAL_PREFIX}3`),
    );
    expect(s3.status).toBe(201);
    sealWorker1Floor2 = s3.body.id;

    await request(app)
      .patch(`/api/seals/${sealWorker2Floor1}/status`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ status: 'checked' })
      .expect(200);
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.$disconnect();
  });

  const reportQuery = { jobId };

  describe('role access', () => {
    it('worker cannot access work-summary (403)', async () => {
      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${worker1Token}`)
        .query(reportQuery);
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('FORBIDDEN');
    });

    it('worker cannot access CSV export (403)', async () => {
      const res = await request(app)
        .get('/api/reports/export/csv')
        .set('Authorization', `Bearer ${worker1Token}`)
        .query(reportQuery);
      expect(res.status).toBe(403);
    });

    it('worker cannot access PDF export (403)', async () => {
      const res = await request(app)
        .get('/api/reports/export/pdf')
        .set('Authorization', `Bearer ${worker1Token}`)
        .query(reportQuery);
      expect(res.status).toBe(403);
    });

    it('management can access work-summary', async () => {
      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${managementToken}`)
        .query(reportQuery);
      expect(res.status).toBe(200);
      expect(res.body.count).toBeGreaterThanOrEqual(3);
      expect(Array.isArray(res.body.rows)).toBe(true);
    });

    it('admin can access work-summary', async () => {
      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${adminToken}`)
        .query(reportQuery);
      expect(res.status).toBe(200);
      expect(res.body.count).toBeGreaterThanOrEqual(3);
    });
  });

  describe('GET /api/reports/work-summary filters', () => {
    it('filters by jobId and returns BE-05 test seals', async () => {
      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${managementToken}`)
        .query({ jobId });
      expect(res.status).toBe(200);
      const numbers = res.body.rows.map((r) => r.cisloUcpavky);
      expect(numbers).toEqual(
        expect.arrayContaining([`${SEAL_PREFIX}1`, `${SEAL_PREFIX}2`, `${SEAL_PREFIX}3`]),
      );
    });

    it('filters by workerId (createdById)', async () => {
      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${managementToken}`)
        .query({ jobId, workerId: worker1Id });
      expect(res.status).toBe(200);
      const numbers = res.body.rows.map((r) => r.cisloUcpavky);
      expect(numbers).toContain(`${SEAL_PREFIX}1`);
      expect(numbers).toContain(`${SEAL_PREFIX}3`);
      expect(numbers).not.toContain(`${SEAL_PREFIX}2`);
    });

    it('filters by status', async () => {
      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${managementToken}`)
        .query({ jobId, status: 'checked' });
      expect(res.status).toBe(200);
      expect(res.body.rows.length).toBeGreaterThanOrEqual(1);
      expect(res.body.rows.every((r) => r.status === 'checked')).toBe(true);
      expect(res.body.rows.some((r) => r.cisloUcpavky === `${SEAL_PREFIX}2`)).toBe(true);
    });

    it('filters by floorId', async () => {
      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${managementToken}`)
        .query({ jobId, floorId: floor2Id });
      expect(res.status).toBe(200);
      const numbers = res.body.rows.map((r) => r.cisloUcpavky);
      expect(numbers).toContain(`${SEAL_PREFIX}3`);
      expect(numbers).not.toContain(`${SEAL_PREFIX}1`);
      expect(numbers).not.toContain(`${SEAL_PREFIX}2`);
    });

    it('filters by date range (from/to)', async () => {
      const today = new Date();
      const from = new Date(today);
      from.setDate(from.getDate() - 1);
      const to = new Date(today);
      to.setDate(to.getDate() + 1);

      const res = await request(app)
        .get('/api/reports/work-summary')
        .set('Authorization', `Bearer ${managementToken}`)
        .query({
          jobId,
          from: from.toISOString(),
          to: to.toISOString(),
        });
      expect(res.status).toBe(200);
      expect(res.body.rows.some((r) => r.cisloUcpavky === `${SEAL_PREFIX}1`)).toBe(true);
    });
  });

  describe('export endpoints', () => {
    it('GET /api/reports/export/csv returns UTF-8 CSV with data', async () => {
      const res = await request(app)
        .get('/api/reports/export/csv')
        .set('Authorization', `Bearer ${managementToken}`)
        .query({ jobId, workerId: worker1Id });
      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toMatch(/text\/csv/);
      expect(res.headers['content-disposition']).toMatch(/soupis-praci\.csv/);
      expect(res.text.startsWith('\uFEFF')).toBe(true);
      expect(res.text).toContain('Číslo ucpávky');
      expect(res.text).toContain(`${SEAL_PREFIX}1`);
      expect(res.text).not.toContain(`${SEAL_PREFIX}2`);
    });

    it('GET /api/reports/export/pdf returns non-empty PDF', async () => {
      const res = await request(app)
        .get('/api/reports/export/pdf')
        .set('Authorization', `Bearer ${managementToken}`)
        .query({ jobId, floorId: floor1Id })
        .buffer(true)
        .parse((res, callback) => {
          const chunks = [];
          res.on('data', (chunk) => chunks.push(chunk));
          res.on('end', () => callback(null, Buffer.concat(chunks)));
        });

      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toMatch(/application\/pdf/);
      expect(res.headers['content-disposition']).toMatch(/soupis-praci\.pdf/);
      expect(Buffer.isBuffer(res.body)).toBe(true);
      expect(res.body.length).toBeGreaterThan(100);
      expect(res.body.subarray(0, 4).toString()).toBe('%PDF');
    });

    it('admin can export CSV', async () => {
      const res = await request(app)
        .get('/api/reports/export/csv')
        .set('Authorization', `Bearer ${adminToken}`)
        .query({ jobId });
      expect(res.status).toBe(200);
      expect(res.text).toContain('Stavba');
    });
  });
});
