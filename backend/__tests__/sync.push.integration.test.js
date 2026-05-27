import { randomUUID } from 'crypto';
import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const DEVICE_ID = 'be04-test-device';
const SEAL_PREFIX = '9904';

function sealCreatePayload(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    system: 'Sync test',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
  };
}

function sealMutation(overrides) {
  return {
    mutationId: randomUUID(),
    deviceId: DEVICE_ID,
    entityType: 'seal',
    operation: 'create',
    payload: {},
    ...overrides,
  };
}

describe('POST /api/sync/push (BE-04)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floorId;

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '1234' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function push(token, mutations) {
    return request(app)
      .post('/api/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send({ mutations });
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    managementToken = await login('vedeni');

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.syncMutation.deleteMany({
      where: { deviceId: DEVICE_ID },
    });
    await prisma.$disconnect();
  });

  it('creates a seal via sync mutation', async () => {
    const sealNumber = `${SEAL_PREFIX}1`;
    const mutationId = randomUUID();
    const res = await push(workerToken, [
      sealMutation({
        mutationId,
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);

    expect(res.status).toBe(200);
    expect(res.body.results).toHaveLength(1);
    expect(res.body.results[0]).toMatchObject({
      mutationId,
      status: 'ok',
    });
    expect(res.body.results[0].entityId).toEqual(expect.any(String));

    const seal = await prisma.seal.findFirst({
      where: { sealNumber, floorId, deletedAt: null },
    });
    expect(seal).toBeTruthy();
    expect(seal.id).toBe(res.body.results[0].entityId);
  });

  it('returns already_processed for duplicate mutationId (idempotence)', async () => {
    const sealNumber = `${SEAL_PREFIX}2`;
    const mutationId = randomUUID();
    const mut = sealMutation({
      mutationId,
      operation: 'create',
      payload: sealCreatePayload(jobId, floorId, sealNumber),
    });

    const first = await push(workerToken, [mut]);
    expect(first.body.results[0].status).toBe('ok');
    const entityId = first.body.results[0].entityId;

    const second = await push(workerToken, [mut]);
    expect(second.status).toBe(200);
    expect(second.body.results[0]).toMatchObject({
      mutationId,
      status: 'already_processed',
      entityId,
    });

    const count = await prisma.seal.count({
      where: { sealNumber, floorId, deletedAt: null },
    });
    expect(count).toBe(1);
  });

  it('returns conflict for duplicate seal number on same floor', async () => {
    const sealNumber = `${SEAL_PREFIX}3`;
    const first = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    expect(first.body.results[0].status).toBe('ok');

    const duplicate = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    expect(duplicate.status).toBe(200);
    expect(duplicate.body.results[0].status).toBe('conflict');
    expect(duplicate.body.results[0].conflict).toMatch(/duplicit/i);
  });

  it('rejects worker update on invoiced (locked) seal', async () => {
    const sealNumber = `${SEAL_PREFIX}4`;
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    const sealId = createRes.body.results[0].entityId;

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

    const seal = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(seal.status).toBe('invoiced');

    const updateRes = await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: seal.version,
        payload: {
          id: sealId,
          location: 'Worker sync edit',
        },
      }),
    ]);

    expect(updateRes.body.results[0].status).toBe('conflict');
    expect(updateRes.body.results[0].conflict).toMatch(/zamčena/i);
  });

  it('rejects worker update on checked seal (not editable by worker)', async () => {
    const sealNumber = `${SEAL_PREFIX}5`;
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    const sealId = createRes.body.results[0].entityId;

    await request(app)
      .patch(`/api/seals/${sealId}/status`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ status: 'checked' })
      .expect(200);

    const seal = await prisma.seal.findUnique({ where: { id: sealId } });

    const updateRes = await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: seal.version,
        payload: {
          id: sealId,
          location: 'Worker sync edit checked',
        },
      }),
    ]);

    expect(updateRes.body.results[0].status).toBe('conflict');
    expect(updateRes.body.results[0].conflict).toMatch(/worker nemůže editovat/i);
  });
});
