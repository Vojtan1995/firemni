import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const PREFIX = '7755';

describe('Worksheet price snapshot lock — Task 7', () => {
  const app = createApp();
  let token;
  let jobId;
  let floorId;
  const originalPrices = new Map();

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function createPvcSeal(sealNumber) {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send({
        jobId,
        floorId,
        sealNumber,
        trade: 'vodari',
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
    return res.body;
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
    // Restore original price list prices to avoid polluting other suites.
    for (const [id, price] of originalPrices.entries()) {
      await prisma.priceListItem.update({ where: { id }, data: { priceWithMaterial: price } });
    }
    await prisma.workSheetItem.deleteMany({ where: { sealNumber: { startsWith: PREFIX } } });
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: PREFIX } } });
  });

  it('locks item price at creation; later price-list change does not affect it; new worksheet uses new price', async () => {
    const me = await prisma.user.findUnique({ where: { username: 'vedeni' } });

    // 1) Seal + worksheet + item → snapshot price P1
    const sealA = await createPvcSeal(`${PREFIX}1`);
    const entryA = sealA.entries[0].id;
    const ws1 = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${token}`)
      .send({ jobId, workerIds: [me.id] });
    expect(ws1.status).toBe(201);
    const add1 = await request(app)
      .post(`/api/worksheets/${ws1.body.id}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ sealEntryIds: [entryA] });
    expect(add1.status).toBe(201);

    const ws1Detail = await request(app)
      .get(`/api/worksheets/${ws1.body.id}`)
      .set('Authorization', `Bearer ${token}`);
    const item1 = ws1Detail.body.items[0];
    expect(item1.unitPrice).not.toBeNull();
    const p1 = Number(item1.unitPrice);
    expect(item1.priceListVersion).toBeTruthy();

    // 2) Change the active price list (multiply all active prices ×10)
    const activeList = await prisma.priceList.findFirst({
      where: { active: true },
      include: { items: { where: { active: true } } },
    });
    for (const it of activeList.items) {
      originalPrices.set(it.id, it.priceWithMaterial);
      await prisma.priceListItem.update({
        where: { id: it.id },
        data: { priceWithMaterial: Number(it.priceWithMaterial) * 10 },
      });
    }

    // 3) Existing worksheet item price is unchanged (locked snapshot)
    const ws1After = await request(app)
      .get(`/api/worksheets/${ws1.body.id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(Number(ws1After.body.items[0].unitPrice)).toBeCloseTo(p1, 2);

    // 4) New worksheet for a new entry uses the NEW (×10) price
    const sealB = await createPvcSeal(`${PREFIX}2`);
    const entryB = sealB.entries[0].id;
    const ws2 = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${token}`)
      .send({ jobId, workerIds: [me.id] });
    expect(ws2.status).toBe(201);
    const add2 = await request(app)
      .post(`/api/worksheets/${ws2.body.id}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ sealEntryIds: [entryB] });
    expect(add2.status).toBe(201);
    const ws2Detail = await request(app)
      .get(`/api/worksheets/${ws2.body.id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(Number(ws2Detail.body.items[0].unitPrice)).toBeCloseTo(p1 * 10, 2);
  });
});
