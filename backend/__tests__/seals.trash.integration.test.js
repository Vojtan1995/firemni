import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const TRASH_PREFIX = '9910';

describe('Seals trash and restore (admin)', () => {
  const app = createApp();
  let adminToken;
  let managementToken;
  let workerToken;
  let jobId;
  let floorId;
  let sealId;

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    adminToken = await login('admin');
    managementToken = await login('vedeni');
    workerToken = await login('worker1');

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;

    const createRes = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber: `${TRASH_PREFIX}1`,
        system: 'Trash test',
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
    expect(createRes.status).toBe(201);
    sealId = createRes.body.id;

    await request(app)
      .delete(`/api/seals/${sealId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ reason: 'test trash' })
      .expect(200);
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: TRASH_PREFIX } } });
    await prisma.$disconnect();
  });

  it('admin can list deleted seals in trash', async () => {
    const res = await request(app)
      .get('/api/seals/trash')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    const found = res.body.find((s) => s.id === sealId);
    expect(found).toBeDefined();
    expect(found.entityType).toBe('seal');
    expect(found.sealNumber).toBe(`${TRASH_PREFIX}1`);
    expect(found.stavba).toBe('12345678');
    expect(found.patro).toBeTruthy();
    expect(found.deletedAt).toBeTruthy();
  });

  it('management cannot access trash', async () => {
    const res = await request(app)
      .get('/api/seals/trash')
      .set('Authorization', `Bearer ${managementToken}`);
    expect(res.status).toBe(403);
  });

  it('worker cannot access trash', async () => {
    const res = await request(app)
      .get('/api/seals/trash')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('admin can restore deleted seal', async () => {
    const res = await request(app)
      .patch(`/api/seals/${sealId}/restore`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.deletedAt).toBeNull();

    const trashRes = await request(app)
      .get('/api/seals/trash')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(trashRes.body.some((s) => s.id === sealId)).toBe(false);
  });
});
