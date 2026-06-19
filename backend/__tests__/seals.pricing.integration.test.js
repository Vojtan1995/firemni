import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';
import { v4 as uuidv4 } from 'uuid';

const SEAL_PREFIX = '881';

describe('Seals pricing with dimensions', () => {
  const app = createApp();
  let workerToken;
  let jobId;
  let floorId;

  beforeAll(async () => {
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ username: 'worker1', pin: '123456' });
    workerToken = loginRes.body.token;

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;

    const list = await prisma.priceList.findFirst({
      where: { active: true },
      include: { items: true },
    });
    if (list && !list.items.some((i) => i.sizeLabel === 'Plocha' && i.unit === 'm2')) {
      await prisma.priceListItem.create({
        data: {
          id: uuidv4(),
          priceListId: list.id,
          category: 'PROSTUPY',
          sizeLabel: 'Plocha',
          unit: 'm2',
          priceWithMaterial: 980,
          priceWithoutMaterial: 980,
          sortOrder: 999,
          active: true,
        },
      });
    }
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.$disconnect();
  });

  it('prices VZT entry with mb from dimensions', async () => {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber: `${SEAL_PREFIX}01`,
        trade: 'elektrikari',
        system: 'Intuseal',
        construction: 'Stěna',
        location: 'Test',
        fireRating: 'EI 60',
        entries: [
          {
            entryType: 'VZT',
            dimension: '500x300 mm',
            quantity: 1,
            insulation: 'žádná',
            materials: ['Pěna'],
            itemLengthMm: 500,
            itemWidthMm: 300,
          },
        ],
      });

    expect(res.status).toBe(201);
    const entry = res.body.entries[0];
    expect(entry.unit).toBe('mb');
    expect(Number(entry.quantity)).toBeCloseTo(3.2, 3);
    expect(Number(entry.calculatedLinearMeters)).toBeCloseTo(3.2, 3);
    expect(entry.unitPrice).not.toBeNull();
    expect(Number(entry.totalPrice)).toBeCloseTo(Number(entry.unitPrice) * 3.2, 0);
  });

  it('prices PROSTUP with net area after VZT deduction', async () => {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber: `${SEAL_PREFIX}02`,
        trade: 'elektrikari',
        system: 'Intuseal',
        construction: 'Stěna',
        location: 'Test',
        fireRating: 'EI 60',
        openingLengthMm: 1000,
        openingWidthMm: 800,
        entries: [
          {
            entryType: 'PROSTUP',
            dimension: '1000x800 mm',
            quantity: 1,
            insulation: 'nehořlavá',
            materials: ['Pěna'],
          },
          {
            entryType: 'VZT',
            dimension: '500x300 mm',
            quantity: 1,
            insulation: 'žádná',
            materials: ['Pěna'],
            itemLengthMm: 500,
            itemWidthMm: 300,
          },
        ],
      });

    expect(res.status).toBe(201);
    const prostup = res.body.entries.find((e) => e.entryType === 'PROSTUP');
    expect(prostup.unit).toBe('m2');
    // Task 5: exaktní odečet bez +50 mm → 0,80 m² − 0,15 m² = 0,65 m²
    expect(Number(prostup.calculatedNetAreaM2)).toBeCloseTo(0.65, 3);
    expect(Number(prostup.quantity)).toBeCloseTo(0.65, 3);
    expect(prostup.unitPrice).not.toBeNull();
  });

  it('rejects a seal where deduction exceeds the opening area (Task 5)', async () => {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber: `${SEAL_PREFIX}03`,
        trade: 'vzduchari',
        system: 'Intuseal',
        construction: 'Stěna',
        location: 'Test',
        fireRating: 'EI 60',
        openingLengthMm: 500,
        openingWidthMm: 500, // 0,25 m²
        entries: [
          {
            entryType: 'PROSTUP',
            dimension: '500x500 mm',
            quantity: 1,
            insulation: 'nehořlavá',
            materials: ['Pěna'],
          },
          {
            entryType: 'VZT',
            dimension: '1000x1000 mm',
            quantity: 1,
            insulation: 'žádná',
            materials: ['Pěna'],
            itemLengthMm: 1000,
            itemWidthMm: 1000, // 1,0 m² > 0,25 m²
          },
        ],
      });
    expect(res.status).toBe(400);
    expect(String(res.body.error ?? '')).toContain(
      'Odečtená plocha je větší než celková plocha prostupu',
    );
  });
});
