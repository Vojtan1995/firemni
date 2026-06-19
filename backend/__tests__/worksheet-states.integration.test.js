import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const PREFIX = '7766';

describe('Worksheet states (Rozpracovaný/Odevzdaný/Schválený/Fakturovaný) — Task 8', () => {
  const app = createApp();
  let workerToken;
  let vedeniToken;
  let jobId;
  let floorId;
  let workerId;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function createSealEntry(sealNumber) {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber,
        trade: 'plynari',
        system: 'Intuseal',
        construction: 'Stěna',
        location: 'Chodba',
        fireRating: 'EI 60',
        entries: [
          {
            entryType: 'PVC',
            dimension: 'Ø50',
            quantity: 1,
            insulation: 'žádná',
            materials: ['Pěna'],
          },
        ],
      });
    expect(res.status).toBe(201);
    return res.body.entries[0].id;
  }

  async function setStatus(token, wsId, status, comment) {
    return request(app)
      .patch(`/api/worksheets/${wsId}/status`)
      .set('Authorization', `Bearer ${token}`)
      .send({ status, ...(comment ? { comment } : {}) });
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    vedeniToken = await login('vedeni');
    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;
    const me = await prisma.user.findUnique({ where: { username: 'worker1' } });
    workerId = me.id;
  });

  afterAll(async () => {
    await prisma.workSheetItem.deleteMany({ where: { sealNumber: { startsWith: PREFIX } } });
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: PREFIX } } });
  });

  async function freshWorksheet(sealNumber) {
    const entryId = await createSealEntry(sealNumber);
    const ws = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ jobId });
    expect(ws.status).toBe(201);
    const add = await request(app)
      .post(`/api/worksheets/${ws.body.id}/items`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ sealEntryIds: [entryId] });
    expect(add.status).toBe(201);
    return ws.body.id;
  }

  it('worker can submit (Odevzdaný) but not edit/transition afterwards', async () => {
    const wsId = await freshWorksheet(`${PREFIX}1`);
    expect((await setStatus(workerToken, wsId, 'submitted')).status).toBe(200);
    // worker cannot move it forward
    expect((await setStatus(workerToken, wsId, 'reviewed')).status).toBe(403);
    // worker cannot add items to a submitted (non-draft) worksheet
    const entryId = await createSealEntry(`${PREFIX}12`);
    const add = await request(app)
      .post(`/api/worksheets/${wsId}/items`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ sealEntryIds: [entryId] });
    expect(add.status).toBe(400);
  });

  it('vedení returns to Rozpracovaný only with a mandatory comment', async () => {
    const wsId = await freshWorksheet(`${PREFIX}2`);
    await setStatus(workerToken, wsId, 'submitted');
    const noComment = await setStatus(vedeniToken, wsId, 'draft');
    expect(noComment.status).toBe(400);
    const withComment = await setStatus(vedeniToken, wsId, 'draft', 'Doplňte rozměry');
    expect(withComment.status).toBe(200);
    expect(withComment.body.status).toBe('draft');
  });

  it('Schválený can be marked Fakturovaný directly and is then locked', async () => {
    const wsId = await freshWorksheet(`${PREFIX}3`);
    await setStatus(workerToken, wsId, 'submitted');
    expect((await setStatus(vedeniToken, wsId, 'reviewed')).status).toBe(200);
    // direct reviewed (Schválený) -> invoiced (Fakturovaný)
    expect((await setStatus(vedeniToken, wsId, 'invoiced')).status).toBe(200);
    // Fakturovaný: items cannot be added
    const entryId = await createSealEntry(`${PREFIX}32`);
    const add = await request(app)
      .post(`/api/worksheets/${wsId}/items`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ sealEntryIds: [entryId] });
    expect(add.status).toBe(400);
  });
});
