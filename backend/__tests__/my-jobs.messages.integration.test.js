import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('My jobs and messages (phase 2)', () => {
  const app = createApp();
  let workerToken;
  let vedeniToken;
  let jobId;
  let floorId;

  beforeAll(async () => {
    const worker = await request(app)
      .post('/api/auth/login')
      .send({ username: 'worker1', pin: '123456' });
    workerToken = worker.body.token;

    const vedeni = await request(app)
      .post('/api/auth/login')
      .send({ username: 'vedeni', pin: '123456' });
    vedeniToken = vedeni.body.token;

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;
  });

  afterAll(async () => {
    await prisma.privateMessage.deleteMany({});
    await prisma.$disconnect();
  });

  it('vedeni sees all active jobs in my jobs list', async () => {
    const my = await request(app)
      .get('/api/jobs/my')
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(my.status).toBe(200);
    expect(my.body.length).toBeGreaterThan(0);
    expect(my.body.some((j) => j.id === jobId)).toBe(true);

    const allJobs = await request(app)
      .get('/api/jobs')
      .set('Authorization', `Bearer ${vedeniToken}`);
    const activeIds = allJobs.body.map((j) => j.id);
    expect(my.body.map((j) => j.id).sort()).toEqual(activeIds.sort());
  });

  it('worker sees job after creating a seal', async () => {
    const sealNumber = String(Date.now()).slice(-5);
    const create = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber,
        trade: 'elektrikari',
        system: 'Test',
        construction: 'Stěna',
        location: 'A',
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
    expect(create.status).toBe(201);

    const my = await request(app)
      .get('/api/jobs/my')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(my.status).toBe(200);
    expect(my.body.some((j) => j.id === jobId)).toBe(true);
  });

  it('worker and vedeni can exchange private messages', async () => {
    const worker = await prisma.user.findUnique({ where: { username: 'worker1' } });
    const vedeni = await prisma.user.findUnique({ where: { username: 'vedeni' } });

    const sent = await request(app)
      .post('/api/messages')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ recipientId: vedeni.id, body: 'Ahoj z terénu' });
    expect(sent.status).toBe(201);

    const inbox = await request(app)
      .get('/api/messages')
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(inbox.status).toBe(200);
    expect(inbox.body.some((m) => m.body === 'Ahoj z terénu')).toBe(true);
  });
});
