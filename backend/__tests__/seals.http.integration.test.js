import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const SEAL_PREFIX = '880';

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
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
  };
}

describe('Seals HTTP integration (BE-03)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floor1Id;
  let floor2Id;

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '1234' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function createSeal(token, jobId, floorId, sealNumber) {
    return request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send(sealBody(jobId, floorId, sealNumber));
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
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.$disconnect();
  });

  describe('duplicate seal number via HTTP', () => {
    const sealNumber = `${SEAL_PREFIX}01`;

    it('creates the first seal successfully', async () => {
      const res = await createSeal(workerToken, jobId, floor1Id, sealNumber);
      expect(res.status).toBe(201);
      expect(res.body.sealNumber).toBe(sealNumber);
    });

    it('rejects a second active seal with the same number on the same floor', async () => {
      const res = await createSeal(workerToken, jobId, floor1Id, sealNumber);
      expect(res.status).toBe(409);
      expect(res.body.code).toBe('CONFLICT');
    });

    it('allows the same number on a different floor', async () => {
      const res = await createSeal(workerToken, jobId, floor2Id, sealNumber);
      expect(res.status).toBe(201);
      expect(res.body.floorId).toBe(floor2Id);
    });

    it('allows reusing the number after soft delete on the original floor', async () => {
      const existing = await prisma.seal.findFirst({
        where: { jobId, floorId: floor1Id, sealNumber, deletedAt: null },
      });
      expect(existing).toBeTruthy();

      const del = await request(app)
        .delete(`/api/seals/${existing.id}`)
        .set('Authorization', `Bearer ${workerToken}`);
      expect(del.status).toBe(200);

      const res = await createSeal(workerToken, jobId, floor1Id, sealNumber);
      expect(res.status).toBe(201);
      expect(res.body.sealNumber).toBe(sealNumber);
    });
  });

  describe('status transitions via HTTP', () => {
    let sealId;

    beforeAll(async () => {
      const res = await createSeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}20`);
      expect(res.status).toBe(201);
      sealId = res.body.id;
    });

    it('worker cannot change status', async () => {
      const res = await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ status: 'checked' });
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('FORBIDDEN');
    });

    it('management can change draft → checked', async () => {
      const res = await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ status: 'checked' });
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('checked');
    });

    it('management can change checked → draft', async () => {
      const res = await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ status: 'draft' });
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('draft');
    });

    it('management can change checked → invoiced', async () => {
      await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ status: 'checked' })
        .expect(200);

      const res = await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ status: 'invoiced' });
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('invoiced');
    });
  });

  describe('worker edit rules', () => {
    it('worker can PATCH a checked seal and status reverts to draft', async () => {
      const created = await createSeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}30`);
      expect(created.status).toBe(201);
      const sealId = created.body.id;

      await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ status: 'checked' })
        .expect(200);

      const detail = await request(app)
        .get(`/api/seals/${sealId}`)
        .set('Authorization', `Bearer ${workerToken}`);

      const res = await request(app)
        .patch(`/api/seals/${sealId}`)
        .set('Authorization', `Bearer ${workerToken}`)
        .send({
          baseVersion: detail.body.version,
          location: 'Změna workerem',
        });

      expect(res.status).toBe(200);
      expect(res.body.status).toBe('draft');
      expect(res.body.location).toBe('Změna workerem');
    });

    it('worker cannot PATCH an invoiced seal', async () => {
      const created = await createSeal(workerToken, jobId, floor1Id, `${SEAL_PREFIX}31`);
      expect(created.status).toBe(201);
      const sealId = created.body.id;

      await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ status: 'checked' })
        .expect(200);

      await request(app)
        .patch(`/api/seals/${sealId}/status`)
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ status: 'invoiced' })
        .expect(200);

      const detail = await request(app)
        .get(`/api/seals/${sealId}`)
        .set('Authorization', `Bearer ${workerToken}`);

      const res = await request(app)
        .patch(`/api/seals/${sealId}`)
        .set('Authorization', `Bearer ${workerToken}`)
        .send({
          baseVersion: detail.body.version,
          location: 'Změna workerem',
        });

      expect(res.status).toBe(403);
      expect(res.body.code).toBe('FORBIDDEN');
    });
  });
});
