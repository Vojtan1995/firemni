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
    trade: 'elektrikari',
    system: 'Sync test',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'EL.V.',
        electroInstallationType: 'Svazek',
        dimension: 'Ø20',
        quantity: 2,
        insulation: 'žádná',
        materials: ['Pena', 'Tmel'],
      },
      {
        entryType: 'PVC',
        dimension: 'Ø110',
        quantity: 1,
        insulation: 'hořlavá',
        materials: ['Manzeta'],
      },
    ],
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
      .send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function push(token, mutations) {
    return request(app)
      .post('/api/sync/push')
      .set('Authorization', `Bearer ${token}`)
      .send({ mutations });
  }

  async function pull(token, since) {
    return request(app)
      .get('/api/sync/pull')
      .query({ since: since.toISOString() })
      .set('Authorization', `Bearer ${token}`);
  }

  async function attachTestPhoto(sealId) {
    const worker = await prisma.user.findFirst({ where: { username: 'worker1' } });
    if (!worker) throw new Error('worker1 not found');
    await prisma.sealPhoto.create({
      data: {
        sealId,
        filePath: 'test/sync-photo.webp',
        mimeType: 'image/webp',
        fileSize: 128,
        uploadedById: worker.id,
      },
    });
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
      include: {
        entries: {
          include: { materials: { orderBy: { sortOrder: 'asc' } } },
          orderBy: { sortOrder: 'asc' },
        },
      },
    });
    expect(seal).toBeTruthy();
    expect(seal.id).toBe(res.body.results[0].entityId);
    expect(seal.entries).toHaveLength(2);
    expect(Number(seal.entries[0].quantity)).toBe(2);
    expect(seal.entries[0]).toMatchObject({
      entryType: 'EL.V.',
      electroInstallationType: 'Svazek',
      dimension: 'Ø20',
      insulation: 'žádná',
    });
    expect(seal.entries[0].materials.map((m) => m.material)).toEqual(['Pena', 'Tmel']);
    expect(seal.entries[1].materials.map((m) => m.material)).toEqual(['Manzeta']);
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

  it('returns the stored conflict for duplicate mutationId after a business conflict', async () => {
    const sealNumber = `${SEAL_PREFIX}6`;
    const first = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    expect(first.body.results[0].status).toBe('ok');

    const mutationId = randomUUID();
    const duplicateMutation = sealMutation({
      mutationId,
      operation: 'create',
      payload: sealCreatePayload(jobId, floorId, sealNumber),
    });

    const duplicateFirst = await push(workerToken, [duplicateMutation]);
    expect(duplicateFirst.body.results[0].status).toBe('conflict');
    expect(duplicateFirst.body.results[0].conflict).toMatch(/duplicit/i);

    const duplicateSecond = await push(workerToken, [duplicateMutation]);
    expect(duplicateSecond.body.results[0].status).toBe('conflict');
    expect(duplicateSecond.body.results[0].conflict).toMatch(/duplicit/i);

    const stored = await prisma.syncMutation.findUnique({ where: { mutationId } });
    expect(stored.processedAt).toBeTruthy();
    expect(stored.result.status).toBe('conflict');
  });

  it('does not mark technical/validation errors as processed', async () => {
    const mutationId = randomUUID();
    const invalidMutation = sealMutation({
      mutationId,
      operation: 'create',
      payload: {
        jobId,
        floorId,
        sealNumber: `${SEAL_PREFIX}7`,
        trade: 'elektrikari',
        system: 'Sync test',
        construction: 'Stena',
        location: 'Chodba',
        fireRating: 'EI 60',
      },
    });

    const first = await push(workerToken, [invalidMutation]);
    expect(first.body.results[0].status).toBe('error');

    const stored = await prisma.syncMutation.findUnique({ where: { mutationId } });
    expect(stored.processedAt).toBeNull();
    expect(stored.result.status).toBe('error');

    const second = await push(workerToken, [invalidMutation]);
    expect(second.body.results[0].status).toBe('error');
  });

  it('pull returns tombstones for deleted seals', async () => {
    const sealNumber = `${SEAL_PREFIX}8`;
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    const sealId = createRes.body.results[0].entityId;
    const since = new Date(Date.now() - 1000);

    await request(app)
      .delete(`/api/seals/${sealId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .expect(200);

    const pullRes = await pull(workerToken, since);
    expect(pullRes.status).toBe(200);
    expect(pullRes.body.deleted).toBeTruthy();
    expect(pullRes.body.deleted.seals).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: sealId,
          jobId,
          floorId,
        }),
      ]),
    );
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

    await attachTestPhoto(sealId);

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

  it('worker can update checked seal via sync and status reverts to draft', async () => {
    const sealNumber = `${SEAL_PREFIX}5`;
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    const sealId = createRes.body.results[0].entityId;

    await attachTestPhoto(sealId);

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

    expect(updateRes.body.results[0].status).toBe('ok');
    const updated = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(updated.status).toBe('draft');
    expect(updated.location).toBe('Worker sync edit checked');
  });

  it('worker sync ignores public note on create but saves internalNote', async () => {
    const sealNumber = `${SEAL_PREFIX}9`;
    const createPayload = {
      ...sealCreatePayload(jobId, floorId, sealNumber),
      note: 'Poznámka test',
      internalNote: 'Interní test',
    };
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: createPayload,
      }),
    ]);
    expect(createRes.body.results[0].status).toBe('ok');
    const sealId = createRes.body.results[0].entityId;
    const seal = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(seal.note).toBeNull();
    expect(seal.internalNote).toBe('Interní test');

    const updateRes = await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: seal.version,
        payload: {
          id: sealId,
          internalNote: null,
        },
      }),
    ]);
    expect(updateRes.body.results[0].status).toBe('ok');
    const updated = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(updated.internalNote).toBeNull();
  });

  it('management sync clears public note when payload sends null', async () => {
    const sealNumber = `${SEAL_PREFIX}91`;
    const createPayload = {
      ...sealCreatePayload(jobId, floorId, sealNumber),
      note: 'Poznámka test',
    };
    const createRes = await push(managementToken, [
      sealMutation({
        operation: 'create',
        payload: createPayload,
      }),
    ]);
    expect(createRes.body.results[0].status).toBe('ok');
    const sealId = createRes.body.results[0].entityId;
    const seal = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(seal.note).toBe('Poznámka test');

    const updateRes = await push(managementToken, [
      sealMutation({
        operation: 'update',
        baseVersion: seal.version,
        payload: {
          id: sealId,
          note: null,
        },
      }),
    ]);
    expect(updateRes.body.results[0].status).toBe('ok');
    const updated = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(updated.note).toBeNull();
  });

  it('management can push status mutation via sync', async () => {
    const sealNumber = `${Date.now()}`;
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    expect(createRes.body.results[0].status).toBe('ok');
    const sealId = createRes.body.results[0].entityId;

    await attachTestPhoto(sealId);

    const statusRes = await push(managementToken, [
      sealMutation({
        operation: 'status',
        payload: {
          id: sealId,
          status: 'checked',
        },
      }),
    ]);

    expect(statusRes.status).toBe(200);
    expect(statusRes.body.results[0].status).toBe('ok');
    const seal = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(seal.status).toBe('checked');
  });

  function sealUpdatePayload(sealId, sealNumber, overrides = {}) {
    return {
      id: sealId,
      jobId,
      floorId,
      sealNumber,
      trade: 'elektrikari',
      system: 'Sync test',
      construction: 'Stěna',
      location: 'Chodba',
      fireRating: 'EI 60',
      entries: [
        {
          entryType: 'PVC',
          dimension: 'Ø110',
          quantity: 1,
          insulation: 'hořlavá',
          materials: ['Manzeta'],
        },
      ],
      editReason: 'test edit',
      ...overrides,
    };
  }

  it('auto-merges concurrent edit: keeps server change to a field the client did not touch', async () => {
    const sealNumber = `${SEAL_PREFIX}31`;
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    const sealId = createRes.body.results[0].entityId;
    const v1 = (await prisma.seal.findUnique({ where: { id: sealId } })).version;

    // Změna A (na verzi v1): mění jen system → server v2, system = 'SYSTEM A'.
    const aRes = await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: v1,
        payload: sealUpdatePayload(sealId, sealNumber, {
          system: 'SYSTEM A',
          changedFields: ['system'],
        }),
      }),
    ]);
    expect(aRes.body.results[0].status).toBe('ok');

    // Změna B je „stará" (stále baseVersion v1) a mění jen location. Pole system
    // posílá zastaralé ('SYSTEM STALE'), ale není v changedFields → musí se
    // zachovat serverová hodnota 'SYSTEM A'.
    const bRes = await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: v1,
        payload: sealUpdatePayload(sealId, sealNumber, {
          system: 'SYSTEM STALE',
          location: 'MERGED LOCATION',
          changedFields: ['location'],
        }),
      }),
    ]);
    expect(bRes.body.results[0].status).toBe('ok');
    expect(bRes.body.results[0].autoMerged).toBe(true);

    const merged = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(merged.location).toBe('MERGED LOCATION');
    expect(merged.system).toBe('SYSTEM A');
  });

  it('auto-merge: co-edited field is last-write-wins', async () => {
    const sealNumber = `${SEAL_PREFIX}32`;
    const createRes = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, sealNumber),
      }),
    ]);
    const sealId = createRes.body.results[0].entityId;
    const v1 = (await prisma.seal.findUnique({ where: { id: sealId } })).version;

    await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: v1,
        payload: sealUpdatePayload(sealId, sealNumber, {
          system: 'FIRST',
          changedFields: ['system'],
        }),
      }),
    ]);

    // Stará změna stejného pole (system) na základě v1 → vyhrává poslední zápis.
    const lastRes = await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: v1,
        payload: sealUpdatePayload(sealId, sealNumber, {
          system: 'LAST',
          changedFields: ['system'],
        }),
      }),
    ]);
    expect(lastRes.body.results[0].status).toBe('ok');
    const updated = await prisma.seal.findUnique({ where: { id: sealId } });
    expect(updated.system).toBe('LAST');
  });

  it('duplicate seal number stays a hard conflict even with changedFields', async () => {
    const numberA = `${SEAL_PREFIX}33`;
    const numberB = `${SEAL_PREFIX}34`;
    await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, numberA),
      }),
    ]);
    const createB = await push(workerToken, [
      sealMutation({
        operation: 'create',
        payload: sealCreatePayload(jobId, floorId, numberB),
      }),
    ]);
    const sealBId = createB.body.results[0].entityId;
    const vB = (await prisma.seal.findUnique({ where: { id: sealBId } })).version;

    const dupRes = await push(workerToken, [
      sealMutation({
        operation: 'update',
        baseVersion: vB,
        payload: sealUpdatePayload(sealBId, numberA, {
          changedFields: ['sealNumber'],
        }),
      }),
    ]);
    expect(dupRes.body.results[0].status).toBe('conflict');
    expect(dupRes.body.results[0].conflict).toMatch(/duplicit/i);
  });
});
