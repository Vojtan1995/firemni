import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const SEAL_PREFIX = '881';

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: 'elektrikari',
    system: 'Test systém',
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
}

function repairBody(sealId, overrides = {}) {
  return {
    sealId,
    note: 'Doplněna nová izolace po kontrole',
    trade: 'elektrikari',
    system: 'Opravený systém',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'EL.V.',
        electroInstallationType: 'Svazek',
        dimension: 'Ø20',
        quantity: 1,
        insulation: 'minerální vlna',
        materials: ['Pěna', 'Tmel'],
      },
    ],
    ...overrides,
  };
}

describe('Repairs integration (modul Oprava)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let adminToken;
  let jobId;
  let floorId;
  let foreignJobId;
  let foreignFloorId;
  let foreignSealId;
  const foreignProject = `${Date.now()}`.slice(-8).padStart(8, '0');

  async function login(username) {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    managementToken = await login('vedeni');
    adminToken = await login('admin');

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;

    const vedeniUser = await prisma.user.findUnique({ where: { username: 'vedeni' } });
    const foreignJob = await prisma.job.create({
      data: {
        projectNumber: foreignProject,
        name: 'Cizí stavba (repairs test)',
        createdById: vedeniUser.id,
        floors: { create: { name: 'Přízemí', sortOrder: 0 } },
      },
      include: { floors: true },
    });
    foreignJobId = foreignJob.id;
    foreignFloorId = foreignJob.floors[0].id;

    const foreignSeal = await prisma.seal.create({
      data: {
        jobId: foreignJobId,
        floorId: foreignFloorId,
        sealNumber: '7777',
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
    foreignSealId = foreignSeal.id;
  });

  afterAll(async () => {
    await prisma.sealRepair.deleteMany({
      where: { OR: [{ jobId }, { jobId: foreignJobId }] },
    });
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.seal.deleteMany({ where: { jobId: foreignJobId } });
    await prisma.jobFloor.deleteMany({ where: { jobId: foreignJobId } });
    await prisma.job.deleteMany({ where: { id: foreignJobId } });
    await prisma.$disconnect();
  });

  describe('vytvoření opravy (worker, přístupná ucpávka)', () => {
    let sealId;
    let sealBefore;
    let repairId;

    it('worker vytvoří ucpávku k opravě', async () => {
      const res = await request(app)
        .post('/api/seals')
        .set('Authorization', `Bearer ${workerToken}`)
        .send(sealBody(jobId, floorId, `${SEAL_PREFIX}01`));
      expect(res.status).toBe(201);
      sealId = res.body.id;
      sealBefore = res.body;
    });

    it('vytvoření opravy bez poznámky vrací 400 (poznámka je povinná)', async () => {
      const body = repairBody(sealId);
      delete body.note;
      const res = await request(app)
        .post('/api/repairs')
        .set('Authorization', `Bearer ${workerToken}`)
        .send(body);
      expect(res.status).toBe(400);
    });

    it('worker vytvoří opravu k ucpávce, ke které má přístup → 201', async () => {
      const res = await request(app)
        .post('/api/repairs')
        .set('Authorization', `Bearer ${workerToken}`)
        .send(repairBody(sealId));
      expect(res.status).toBe(201);
      expect(res.body.sealId).toBe(sealId);
      expect(res.body.note).toBe('Doplněna nová izolace po kontrole');
      expect(res.body.changedFields).toEqual(
        expect.arrayContaining(['system', 'entries']),
      );
      repairId = res.body.id;
    });

    it('původní ucpávka se po vytvoření opravy nezmění', async () => {
      const res = await request(app)
        .get(`/api/seals/${sealId}`)
        .set('Authorization', `Bearer ${workerToken}`);
      expect(res.status).toBe(200);
      expect(res.body.version).toBe(sealBefore.version);
      expect(res.body.system).toBe(sealBefore.system);
      expect(res.body.entries[0].insulation).toBe(
        sealBefore.entries[0].insulation,
      );
    });

    it('detail opravy odkazuje na původní ucpávku a obsahuje snapshot', async () => {
      const res = await request(app)
        .get(`/api/repairs/${repairId}`)
        .set('Authorization', `Bearer ${workerToken}`);
      expect(res.status).toBe(200);
      expect(res.body.sealId).toBe(sealId);
      expect(res.body.originalSnapshot.system).toBe('Test systém');
      expect(res.body.repairData.system).toBe('Opravený systém');
      expect(res.body.changedFields).toContain('system');
    });

    it('vedení/admin vidí seznam oprav', async () => {
      const res = await request(app)
        .get('/api/repairs')
        .set('Authorization', `Bearer ${managementToken}`);
      expect(res.status).toBe(200);
      expect(res.body.some((r) => r.id === repairId)).toBe(true);
    });

    it('export vybraných oprav funguje pro vedení', async () => {
      const res = await request(app)
        .post('/api/repairs/bulk-export/csv')
        .set('Authorization', `Bearer ${managementToken}`)
        .send({ ids: [repairId] });
      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toContain('text/csv');
      expect(res.text).toContain('Doplněna nová izolace po kontrole');
    });

    it('export oprav je workerovi zakázán (403)', async () => {
      const res = await request(app)
        .post('/api/repairs/bulk-export/csv')
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ ids: [repairId] });
      expect(res.status).toBe(403);
    });
  });

  describe('anonymizace autora a práva na cizí zakázku', () => {
    let sealId;
    let adminRepairId;

    it('admin vytvoří ucpávku a opravu na demo zakázce (bypass participant check)', async () => {
      const sealRes = await request(app)
        .post('/api/seals')
        .set('Authorization', `Bearer ${adminToken}`)
        .send(sealBody(jobId, floorId, `${SEAL_PREFIX}02`));
      expect(sealRes.status).toBe(201);
      sealId = sealRes.body.id;

      const repairRes = await request(app)
        .post('/api/repairs')
        .set('Authorization', `Bearer ${adminToken}`)
        .send(repairBody(sealId));
      expect(repairRes.status).toBe(201);
      adminRepairId = repairRes.body.id;
    });

    it('worker nevidí cizí osobní údaje – admin je v seznamu anonymizován', async () => {
      const res = await request(app)
        .get('/api/repairs')
        .set('Authorization', `Bearer ${workerToken}`);
      expect(res.status).toBe(200);
      const entry = res.body.find((r) => r.id === adminRepairId);
      expect(entry).toBeDefined();
      expect(entry.createdBy.displayName).toBe('Administrátor');
      expect(entry.createdBy.username).toBe('admin');
    });

    it('worker bez účasti na cizí zakázce nemůže vytvořit opravu → zakázáno', async () => {
      const res = await request(app)
        .post('/api/repairs')
        .set('Authorization', `Bearer ${workerToken}`)
        .send(repairBody(foreignSealId));
      expect([403, 404]).toContain(res.status);
    });

    it('worker nevidí detail opravy cizí zakázky', async () => {
      const foreignRepair = await prisma.sealRepair.create({
        data: {
          sealId: foreignSealId,
          jobId: foreignJobId,
          floorId: foreignFloorId,
          sealNumber: '7777',
          note: 'Cizí oprava',
          originalSnapshot: { trade: 'elektrikari' },
          repairData: { trade: 'elektrikari' },
          changedFields: [],
          createdById: (await prisma.user.findUnique({ where: { username: 'vedeni' } })).id,
        },
      });
      const res = await request(app)
        .get(`/api/repairs/${foreignRepair.id}`)
        .set('Authorization', `Bearer ${workerToken}`);
      expect(res.status).toBe(403);
      await prisma.sealRepair.delete({ where: { id: foreignRepair.id } });
    });
  });
});
