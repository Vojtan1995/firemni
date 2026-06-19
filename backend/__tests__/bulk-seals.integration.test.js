import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const SEAL_PREFIX = '883';
const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  'base64',
);

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: 'elektrikari',
    system: 'Test',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'EL.V.',
        electroInstallationType: 'Svazek',
        dimension: 'Ø20',
        quantity: 1,
        insulation: 'žádná',
        materials: ['Pěna'],
      },
    ],
  };
}

describe('Bulk seals operations (task 4.3)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floor1Id;
  let floor2Id;
  const createdSealIds = [];

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function createSeal(token, jobId, floorId, sealNumber) {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send(sealBody(jobId, floorId, sealNumber));
    if (res.status === 201) createdSealIds.push(res.body.id);
    return res;
  }

  async function addPhoto(token, sealId) {
    return request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${token}`)
      .attach('photo', tinyPng, { filename: 'photo.png', contentType: 'image/png' });
  }

  async function createReadySeal(token, jobId, floorId, sealNumber) {
    const created = await createSeal(token, jobId, floorId, sealNumber);
    if (created.status === 201) {
      const photo = await addPhoto(token, created.body.id);
      expect(photo.status).toBe(201);
    }
    return created;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    managementToken = await login('vedeni');

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floor1Id = jobRes.body.floors[0].id;
    floor2Id = jobRes.body.floors[1].id;
  });

  afterAll(async () => {
    if (createdSealIds.length) {
      await prisma.seal.deleteMany({ where: { id: { in: createdSealIds } } });
    }
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.$disconnect();
  });

  describe('POST /api/seals/bulk-status', () => {
    it('approves multiple drafts and reports partial failures', async () => {
      const ok1 = await createReadySeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}01`);
      const ok2 = await createReadySeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}02`);
      expect(ok1.status).toBe(201);
      expect(ok2.status).toBe(201);

      const fakeId = '00000000-0000-4000-8000-000000000099';
      const res = await request(app)
        .post('/api/seals/bulk-status')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({
          ids: [ok1.body.id, ok2.body.id, fakeId],
          status: 'checked',
        });

      expect(res.status).toBe(200);
      expect(res.body.updated).toBe(2);
      expect(res.body.failed).toBe(1);
      expect(res.body.seals).toHaveLength(2);
      expect(res.body.errors).toHaveLength(1);
      expect(res.body.errors[0].id).toBe(fakeId);
    });

    it('returns drafts with mandatory comment', async () => {
      const created = await createReadySeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}03`);
      expect(created.status).toBe(201);

      await request(app)
        .post('/api/seals/bulk-status')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ ids: [created.body.id], status: 'checked' })
        .expect(200);

      const res = await request(app)
        .post('/api/seals/bulk-status')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ ids: [created.body.id], status: 'draft' });

      expect(res.status).toBe(200);
      expect(res.body.updated).toBe(0);
      expect(res.body.failed).toBe(1);
      expect(res.body.errors[0].message).toMatch(/komentář/i);

      const withComment = await request(app)
        .post('/api/seals/bulk-status')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({
          ids: [created.body.id],
          status: 'draft',
          comment: 'Nutná oprava',
        });
      expect(withComment.status).toBe(200);
      expect(withComment.body.updated).toBe(1);
    });
  });

  describe('POST /api/seals/bulk-move', () => {
    it('moves seals to another floor in the same job', async () => {
      const created = await createSeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}10`);
      expect(created.status).toBe(201);

      const res = await request(app)
        .post('/api/seals/bulk-move')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ ids: [created.body.id], floorId: floor2Id });

      expect(res.status).toBe(200);
      expect(res.body.moved).toBe(1);
      expect(res.body.failed).toBe(0);
      expect(res.body.seals[0].floorId).toBe(floor2Id);
      expect(res.body.targetFloorName).toBeTruthy();
    });

    it('rejects duplicate seal number on target floor', async () => {
      const num = `${SEAL_PREFIX}11`;
      const onFloor2 = await createSeal(workerToken, jobId, floor2Id, num);
      const onFloor1 = await createSeal(workerToken, jobId, floor1Id, num);
      expect(onFloor2.status).toBe(201);
      expect(onFloor1.status).toBe(201);

      const res = await request(app)
        .post('/api/seals/bulk-move')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ ids: [onFloor1.body.id], floorId: floor2Id });

      expect(res.status).toBe(200);
      expect(res.body.moved).toBe(0);
      expect(res.body.failed).toBe(1);
      expect(res.body.errors[0].message).toMatch(/duplicit/i);
    });
  });

  describe('POST /api/seals/bulk-export/csv', () => {
    it('exports readable seals as CSV with BOM', async () => {
      const created = await createSeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}20`);
      expect(created.status).toBe(201);

      const res = await request(app)
        .post('/api/seals/bulk-export/csv')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ ids: [created.body.id] });

      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toMatch(/text\/csv/);
      const text = res.text;
      expect(text.charCodeAt(0)).toBe(0xfeff);
      expect(text).toContain('Číslo ucpávky');
      expect(text).toContain(`${SEAL_PREFIX}20`);
    });

    it('worker can export accessible seals', async () => {
      const created = await createSeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}21`);
      expect(created.status).toBe(201);

      const res = await request(app)
        .post('/api/seals/bulk-export/csv')
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ ids: [created.body.id] });

      expect(res.status).toBe(200);
      expect(res.text).toContain(`${SEAL_PREFIX}21`);
    });
  });
});
