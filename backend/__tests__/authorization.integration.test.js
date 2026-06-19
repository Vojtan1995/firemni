import { randomUUID } from 'crypto';
import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('Authorization (wave 1)', () => {
  const app = createApp();
  let worker1Token;
  let worker2Token;
  let vedeniToken;
  let demoJobId;
  let demoFloorId;
  let foreignJobId;
  let foreignFloorId;
  let foreignSealId;
  const foreignProject = `${Date.now()}`.slice(-8).padStart(8, '0');

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    worker1Token = await login('worker1');
    worker2Token = await login('worker2');
    vedeniToken = await login('vedeni');

    const demoJob = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${worker1Token}`);
    expect(demoJob.status).toBe(200);
    demoJobId = demoJob.body.id;
    demoFloorId = demoJob.body.floors[0].id;

    const vedeniUser = await prisma.user.findUnique({ where: { username: 'vedeni' } });
    if (!vedeniUser) throw new Error('vedeni user missing');
    const foreignJob = await prisma.job.create({
      data: {
        projectNumber: foreignProject,
        name: 'Cizí stavba',
        createdById: vedeniUser.id,
        floors: { create: { name: 'Přízemí', sortOrder: 0 } },
      },
      include: { floors: true },
    });
    foreignJobId = foreignJob.id;
    foreignFloorId = foreignJob.floors[0].id;

    const seal = await prisma.seal.create({
      data: {
        jobId: foreignJobId,
        floorId: foreignFloorId,
        sealNumber: '9999',
        trade: 'elektrikari',
        system: 'Test',
        construction: 'Stěna',
        location: 'Sklep',
        fireRating: 'EI 60',
        createdById: vedeniUser.id,
        updatedById: vedeniUser.id,
        entries: {
          create: {
            entryType: 'EL.V.',
            electroInstallationType: 'Svazek',
            dimension: '50',
            quantity: 1,
            insulation: 'žádná',
            materials: { create: [{ material: 'Pena', sortOrder: 0 }] },
          },
        },
      },
    });
    foreignSealId = seal.id;
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({ where: { jobId: foreignJobId } });
    await prisma.jobFloor.deleteMany({ where: { jobId: foreignJobId } });
    await prisma.job.deleteMany({ where: { id: foreignJobId } });
  });

  it('worker without assignment cannot GET floors directly → 403', async () => {
    const res = await request(app)
      .get(`/api/jobs/${foreignJobId}/floors`)
      .set('Authorization', `Bearer ${worker1Token}`);
    expect(res.status).toBe(403);
  });

  it('worker with assignment can GET demo job by number → 200', async () => {
    const res = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${worker1Token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(demoJobId);
  });

  it('worker cannot GET foreign seal by id → 403', async () => {
    const res = await request(app)
      .get(`/api/seals/${foreignSealId}`)
      .set('Authorization', `Bearer ${worker1Token}`);
    expect(res.status).toBe(403);
  });

  it('worker cannot list seals on foreign floor → 403', async () => {
    const res = await request(app)
      .get(`/api/seals/floors/${foreignFloorId}/seals`)
      .set('Authorization', `Bearer ${worker1Token}`);
    expect(res.status).toBe(403);
  });

  it('worker cannot create seal with floor from another job → 400', async () => {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${worker1Token}`)
      .send({
        jobId: demoJobId,
        floorId: foreignFloorId,
        sealNumber: '8888',
        trade: 'elektrikari',
        system: 'Test',
        construction: 'Stěna',
        location: 'Chodba',
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
      });
    expect(res.status).toBe(400);
  });

  it('sync pull for worker returns only participant jobs', async () => {
    const res = await request(app)
      .get('/api/sync/pull')
      .query({ since: new Date(0).toISOString() })
      .set('Authorization', `Bearer ${worker1Token}`);
    expect(res.status).toBe(200);
    const jobIds = res.body.jobs.map((j) => j.id);
    expect(jobIds).toContain(demoJobId);
    expect(jobIds).not.toContain(foreignJobId);
    expect(res.body.serverTime).toBeDefined();
    expect(typeof res.body.hasMore).toBe('boolean');
  });

  it('unknown sync entity returns conflict, not ok', async () => {
    const res = await request(app)
      .post('/api/sync/push')
      .set('Authorization', `Bearer ${worker1Token}`)
      .send({
        mutations: [
          {
            mutationId: randomUUID(),
            deviceId: 'auth-test',
            entityType: 'unknown_entity',
            operation: 'create',
            payload: {},
          },
        ],
      });
    expect(res.status).toBe(200);
    expect(res.body.results[0].status).toBe('conflict');
  });

  it('worker2 can edit worker1 seal on same assigned job (collaboration)', async () => {
    const create = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${worker1Token}`)
      .send({
        jobId: demoJobId,
        floorId: demoFloorId,
        sealNumber: `${Date.now()}`.slice(-4),
        trade: 'elektrikari',
        system: 'RBAC',
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
      });
    expect(create.status).toBe(201);

    const patch = await request(app)
      .patch(`/api/seals/${create.body.id}`)
      .set('Authorization', `Bearer ${worker2Token}`)
      .send({ note: 'Edited by worker2', baseVersion: create.body.version });
    expect(patch.status).toBe(200);
  });

  it('worker cannot access foreign job via reports jobId → 403', async () => {
    const res = await request(app)
      .get('/api/reports/work-summary')
      .query({ jobId: foreignJobId })
      .set('Authorization', `Bearer ${worker1Token}`);
    expect(res.status).toBe(403);
  });
});
