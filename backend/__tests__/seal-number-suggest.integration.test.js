import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const PREFIX = 'SNS';

describe('Suggest next seal number (lowest free)', () => {
  const app = createApp();
  let workerToken;
  let vedeniToken;
  let jobId;
  let floorId;
  const createdSealIds = [];

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  function sealBody(sealNumber) {
    return {
      jobId,
      floorId,
      sealNumber,
      trade: 'elektrikari',
      system: 'WS',
      construction: 'Stěna',
      location: 'Test',
      fireRating: 'EI 60',
      entries: [
        {
          entryType: 'EL.V.',
          electroInstallationType: 'Svazek',
          dimension: '50',
          quantity: 1,
          insulation: 'žádná',
          materials: ['Pena'],
        },
      ],
    };
  }

  async function createSeal(sealNumber) {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send(sealBody(sealNumber));
    expect(res.status).toBe(201);
    createdSealIds.push(res.body.id);
    return res.body;
  }

  async function suggest() {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floorId}/next-seal-number`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    return res.body.nextSealNumber;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    vedeniToken = await login('vedeni');
    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;

    const floor = await request(app)
      .post(`/api/jobs/${jobId}/floors`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ name: `${PREFIX}-${Date.now()}` });
    expect(floor.status).toBe(201);
    floorId = floor.body.id;
  });

  afterAll(async () => {
    if (createdSealIds.length > 0) {
      await prisma.seal.deleteMany({ where: { id: { in: createdSealIds } } });
    }
    if (floorId) {
      await prisma.jobFloor.deleteMany({ where: { id: floorId } });
    }
  });

  it('empty floor suggests 1', async () => {
    expect(String(await suggest())).toBe('1');
  });

  it('1,2,3 -> 4', async () => {
    await createSeal('1');
    await createSeal('2');
    await createSeal('3');
    expect(String(await suggest())).toBe('4');
  });

  it('gap 1,_,3,4 -> 2', async () => {
    // currently 1,2,3 exist; remove 2 to create a gap
    const seal2 = await prisma.seal.findFirst({
      where: { floorId, sealNumber: '2', deletedAt: null },
    });
    await createSeal('4');
    await prisma.seal.update({
      where: { id: seal2.id },
      data: { deletedAt: new Date() },
    });
    // now numeric set = {1,3,4} -> lowest free from min(1) = 2
    expect(String(await suggest())).toBe('2');
  });

  it('backend rejects duplicate number on save (409)', async () => {
    const dup = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send(sealBody('1'));
    expect(dup.status).toBe(409);
  });
});
