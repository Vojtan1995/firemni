import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const SEAL_PREFIX = '8850';

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    system: 'Stats',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'EL.V.',
        dimension: 'Ø20',
        quantity: 1,
        insulation: 'žádná',
        materials: ['Pěna'],
      },
    ],
  };
}

describe('Management dashboard stats (task 5.2)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floor1Id;
  let sealId;

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '1234' });
    expect(res.status).toBe(200);
    return res.body;
  }

  beforeAll(async () => {
    const worker = await login('worker1');
    workerToken = worker.token;
    managementToken = (await login('vedeni')).token;

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floor1Id = jobRes.body.floors[0].id;

    const created = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send(sealBody(jobId, floor1Id, `${SEAL_PREFIX}1`));
    expect(created.status).toBe(201);
    sealId = created.body.id;

    await request(app)
      .patch(`/api/seals/${sealId}/review`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ action: 'returned', comment: 'Opravit rozměr' })
      .expect(200);
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: SEAL_PREFIX } } });
    await prisma.$disconnect();
  });

  it('vedení overview includes extended KPI fields', async () => {
    const res = await request(app)
      .get('/api/stats/overview')
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.body.role).toBe('vedeni');
    expect(res.body).toHaveProperty('returnedSeals');
    expect(res.body).toHaveProperty('missingPhotos');
    expect(res.body).toHaveProperty('syncPending');
    expect(res.body).toHaveProperty('byJobDetailed');
    expect(Array.isArray(res.body.byJobDetailed)).toBe(true);
    expect(res.body.returnedSeals).toBeGreaterThanOrEqual(1);
  });

  it('filters by jobId reduce totals', async () => {
    const all = await request(app)
      .get('/api/stats/overview')
      .set('Authorization', `Bearer ${managementToken}`);
    const filtered = await request(app)
      .get(`/api/stats/overview?jobId=${jobId}`)
      .set('Authorization', `Bearer ${managementToken}`);

    expect(filtered.status).toBe(200);
    expect(filtered.body.filters.jobId).toBe(jobId);
    expect(filtered.body.totalSeals).toBeLessThanOrEqual(all.body.totalSeals);
    const jobRow = filtered.body.byJobDetailed.find((j) => j.jobId === jobId);
    expect(jobRow).toBeTruthy();
    expect(jobRow.returned).toBeGreaterThanOrEqual(1);
  });

  it('worker stats include returned and missing photos', async () => {
    const res = await request(app)
      .get('/api/stats/overview')
      .set('Authorization', `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(res.body.role).toBe('worker');
    expect(res.body.returnedForFix).toBeGreaterThanOrEqual(1);
    expect(res.body.missingPhotos).toBeGreaterThanOrEqual(1);
  });

  it('status filter limits seal counts', async () => {
    const res = await request(app)
      .get(`/api/stats/overview?jobId=${jobId}&status=draft`)
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.body.filters.status).toBe('draft');
    expect(res.body.checked).toBe(0);
    expect(res.body.invoiced).toBe(0);
  });
});
