import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const PREFIX = '7731';

function sealBody(jobId, floorId, sealNumber, trade) {
  const body = {
    jobId,
    floorId,
    sealNumber,
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
  if (trade !== undefined) body.trade = trade;
  return body;
}

describe('Seal trade (Řemeslo) — Task 2', () => {
  const app = createApp();
  let token;
  let jobId;
  let floorId;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    token = await login('vedeni');
    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${token}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: PREFIX } } });
  });

  it('rejects a new seal without trade (400)', async () => {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send(sealBody(jobId, floorId, `${PREFIX}1`));
    expect(res.status).toBe(400);
  });

  it('creates a seal with trade and returns it', async () => {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send(sealBody(jobId, floorId, `${PREFIX}2`, 'vzduchari'));
    expect(res.status).toBe(201);
    expect(res.body.trade).toBe('vzduchari');
  });

  it('old seal without trade defaults to neurceno and is listable', async () => {
    // Simuluj starou ucpávku vloženou bez řemesla (DB default).
    const creator = await prisma.user.findUnique({ where: { username: 'vedeni' } });
    const seal = await prisma.seal.create({
      data: {
        jobId,
        floorId,
        sealNumber: `${PREFIX}3`,
        system: 'Old',
        construction: 'Stěna',
        location: 'Sklep',
        fireRating: 'EI 60',
        createdById: creator.id,
        updatedById: creator.id,
      },
    });
    expect(seal.trade).toBe('neurceno');

    const list = await request(app)
      .get(`/api/seals/floors/${floorId}/seals`)
      .set('Authorization', `Bearer ${token}`);
    expect(list.status).toBe(200);
    const found = list.body.find((s) => s.id === seal.id);
    expect(found).toBeDefined();
    expect(found.trade).toBe('neurceno');
  });

  it('filters seals by trade', async () => {
    const res = await request(app)
      .get(`/api/seals/floors/${floorId}/seals`)
      .query({ trade: 'vzduchari' })
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.length).toBeGreaterThan(0);
    expect(res.body.every((s) => s.trade === 'vzduchari')).toBe(true);
  });
});
