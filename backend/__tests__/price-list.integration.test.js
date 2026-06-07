import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('Price list (read-only for workers)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '1234' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    managementToken = await login('vedeni');
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('worker can GET active price list', async () => {
    const res = await request(app)
      .get('/api/price-list')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.version).toBeTruthy();
    expect(Array.isArray(res.body.items)).toBe(true);
    expect(res.body.items.length).toBeGreaterThan(0);
  });

  it('worker cannot seed price list', async () => {
    const res = await request(app)
      .post('/api/price-list/seed')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('management can seed price list', async () => {
    const res = await request(app)
      .post('/api/price-list/seed')
      .set('Authorization', `Bearer ${managementToken}`);
    expect(res.status).toBe(200);
    expect(res.body.version).toBeTruthy();
  });

  it('GET returns 404 when no active price list exists', async () => {
    await prisma.priceList.updateMany({ data: { active: false } });

    const res = await request(app)
      .get('/api/price-list')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(404);
    expect(res.body.code).toBe('NOT_FOUND');

    await request(app)
      .post('/api/price-list/seed')
      .set('Authorization', `Bearer ${managementToken}`)
      .expect(200);
  });

  it('database rejects two simultaneously active price lists', async () => {
    await prisma.priceList.updateMany({ data: { active: false } });
    const suffix = Date.now();
    const first = await prisma.priceList.create({
      data: {
        version: `test-active-${suffix}-a`,
        validFrom: new Date(),
        active: true,
      },
    });
    await expect(
      prisma.priceList.create({
        data: {
          version: `test-active-${suffix}-b`,
          validFrom: new Date(),
          active: true,
        },
      }),
    ).rejects.toThrow();

    await prisma.priceList.update({ where: { id: first.id }, data: { active: false } });
    await request(app)
      .post('/api/price-list/seed')
      .set('Authorization', `Bearer ${managementToken}`)
      .expect(200);
  });
});
