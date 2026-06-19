import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const PREFIX = '7742';

function baseBody(jobId, floorId, sealNumber, entry) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: 'topenari',
    system: 'Test',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    entries: [
      {
        dimension: 'Ø20',
        quantity: 1,
        insulation: 'žádná',
        materials: ['Pěna'],
        ...entry,
      },
    ],
  };
}

describe('Seal entry types + conditional fields — Task 3', () => {
  const app = createApp();
  let token;
  let jobId;
  let floorId;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function create(sealNumber, entry) {
    return request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send(baseBody(jobId, floorId, sealNumber, entry));
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

  it('accepts the new Měď type', async () => {
    const res = await create(`${PREFIX}1`, { entryType: 'Měď', dimension: 'Ø22' });
    expect(res.status).toBe(201);
    expect(res.body.entries[0].entryType).toBe('Měď');
  });

  it('rejects Ocel without Doizolováno', async () => {
    const res = await create(`${PREFIX}2`, { entryType: 'OCEL' });
    expect(res.status).toBe(400);
  });

  it('accepts Ocel with Doizolováno = Ne', async () => {
    const res = await create(`${PREFIX}3`, { entryType: 'OCEL', steelInsulated: false });
    expect(res.status).toBe(201);
    expect(res.body.entries[0].steelInsulated).toBe(false);
  });

  it('rejects Elektro (EL.V.) without installation subtype', async () => {
    const res = await create(`${PREFIX}4`, { entryType: 'EL.V.' });
    expect(res.status).toBe(400);
  });

  it('rejects an invalid Elektro subtype', async () => {
    const res = await create(`${PREFIX}5`, {
      entryType: 'EL.V.',
      electroInstallationType: 'Neexistuje',
    });
    expect(res.status).toBe(400);
  });

  it('accepts Elektro with subtype Žlab', async () => {
    const res = await create(`${PREFIX}6`, {
      entryType: 'EL.V.',
      electroInstallationType: 'Žlab',
    });
    expect(res.status).toBe(201);
    expect(res.body.entries[0].electroInstallationType).toBe('Žlab');
  });

  it('old Ocel entry without Doizolováno is still displayable', async () => {
    const creator = await prisma.user.findUnique({ where: { username: 'vedeni' } });
    const seal = await prisma.seal.create({
      data: {
        jobId,
        floorId,
        sealNumber: `${PREFIX}7`,
        trade: 'neurceno',
        system: 'Old',
        construction: 'Stěna',
        location: 'Sklep',
        fireRating: 'EI 60',
        createdById: creator.id,
        updatedById: creator.id,
        entries: {
          create: {
            entryType: 'OCEL',
            dimension: 'Ø50',
            quantity: 1,
            insulation: 'žádná',
            // steelInsulated intentionally null (legacy row)
          },
        },
      },
    });
    const res = await request(app)
      .get(`/api/seals/${seal.id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.entries[0].entryType).toBe('OCEL');
    expect(res.body.entries[0].steelInsulated).toBeNull();
  });
});
