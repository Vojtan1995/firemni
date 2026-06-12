import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';
import { markSealChecked } from './helpers/integration-helpers.js';

const WS_TEST_PREFIX = '990';

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    system: 'WS',
    construction: 'Stěna',
    location: 'Test',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'EL.V.',
        dimension: '50',
        quantity: 1,
        insulation: 'žádná',
        materials: ['Pena'],
      },
    ],
  };
}

describe('Worksheets module integration', () => {
  const app = createApp();
  let workerToken;
  let worker2Token;
  let ucetniToken;
  let vedeniToken;
  let adminToken;
  let jobId;
  let workerWorksheetId;
  let worker2WorksheetId;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '1234' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    worker2Token = await login('worker2');
    ucetniToken = await login('ucetni');
    vedeniToken = await login('vedeni');
    adminToken = await login('admin');

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;

    const ws1 = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ jobId });
    expect(ws1.status).toBe(201);
    workerWorksheetId = ws1.body.id;

    const ws2 = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${worker2Token}`)
      .send({ jobId });
    expect(ws2.status).toBe(201);
    worker2WorksheetId = ws2.body.id;
  });

  it('worker opens own worksheet detail', async () => {
    const res = await request(app)
      .get(`/api/worksheets/${workerWorksheetId}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(workerWorksheetId);
    expect(res.body.itemCount).toBeDefined();
    expect(Array.isArray(res.body.statusHistory)).toBe(true);
  });

  it('worker cannot open another worker worksheet (403)', async () => {
    const res = await request(app)
      .get(`/api/worksheets/${worker2WorksheetId}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('worker downloads own worksheet CSV and PDF', async () => {
    const csv = await request(app)
      .get(`/api/worksheets/${workerWorksheetId}/export/csv`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(csv.status).toBe(200);
    expect(csv.headers['content-type']).toMatch(/text\/csv/);

    const pdf = await request(app)
      .get(`/api/worksheets/${workerWorksheetId}/export/pdf`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(pdf.status).toBe(200);
    expect(pdf.headers['content-type']).toMatch(/application\/pdf/);
  });

  it('worker cannot download another worker worksheet (403)', async () => {
    const res = await request(app)
      .get(`/api/worksheets/${worker2WorksheetId}/export/pdf`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('vedeni opens and downloads any worksheet', async () => {
    const detail = await request(app)
      .get(`/api/worksheets/${worker2WorksheetId}`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(detail.status).toBe(200);

    const pdf = await request(app)
      .get(`/api/worksheets/${worker2WorksheetId}/export/pdf`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(pdf.status).toBe(200);
  });

  it('admin opens and downloads any worksheet', async () => {
    const detail = await request(app)
      .get(`/api/worksheets/${workerWorksheetId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(detail.status).toBe(200);

    const csv = await request(app)
      .get(`/api/worksheets/${workerWorksheetId}/export/csv`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(csv.status).toBe(200);
  });

  it('ucetni downloads allowed worksheet', async () => {
    const res = await request(app)
      .get(`/api/worksheets/${workerWorksheetId}/export/csv`)
      .set('Authorization', `Bearer ${ucetniToken}`);
    expect(res.status).toBe(200);
  });

  it('worker cannot change status after submission', async () => {
    const submit = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ status: 'submitted' });
    expect(submit.status).toBe(200);

    const denied = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ status: 'reviewed' });
    expect(denied.status).toBe(403);
  });

  it('vedeni can revert worksheet status backward', async () => {
    const review = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ status: 'reviewed' });
    expect(review.status).toBe(200);

    const ready = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${ucetniToken}`)
      .send({ status: 'ready_for_invoice' });
    expect(ready.status).toBe(200);

    const invoiced = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${ucetniToken}`)
      .send({ status: 'invoiced' });
    expect(invoiced.status).toBe(200);

    const revert = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({
        status: 'ready_for_invoice',
        comment: 'Omylem označeno jako fakturované.',
      });
    expect(revert.status).toBe(200);
    expect(revert.body.status).toBe('ready_for_invoice');
  });

  it('admin can revert worksheet status backward', async () => {
    const revert = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ status: 'reviewed', comment: 'Vráceno ke kontrole' });
    expect(revert.status).toBe(200);
    expect(revert.body.status).toBe('reviewed');
  });

  it('status change creates audit log entry', async () => {
    const logs = await prisma.changeLog.findMany({
      where: {
        entityType: 'worksheet',
        entityId: workerWorksheetId,
        fieldName: 'status',
      },
      orderBy: { createdAt: 'desc' },
      take: 1,
    });
    expect(logs.length).toBeGreaterThan(0);
    expect(logs[0].oldValue).toBeTruthy();
    expect(logs[0].newValue).toBeTruthy();
  });

  it('worker can submit again after management returns to draft', async () => {
    const toDraft = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ status: 'draft', comment: 'Nutná oprava položek' });
    expect(toDraft.status).toBe(200);

    const resubmit = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ status: 'submitted' });
    expect(resubmit.status).toBe(200);
  });

  it('ucetni cannot change non-invoice statuses (403)', async () => {
    const review = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ status: 'reviewed' });
    expect(review.status).toBe(200);

    const denied = await request(app)
      .patch(`/api/worksheets/${workerWorksheetId}/status`)
      .set('Authorization', `Bearer ${ucetniToken}`)
      .send({ status: 'submitted' });
    expect(denied.status).toBe(403);
  });

  describe('worksheet items', () => {
    let jobIdLocal;
    let floorId;
    let populateFloorId;
    let populateWorksheetId;
    let duplicateWs1Id;
    let duplicateWs2Id;

    beforeAll(async () => {
      const jobRes = await request(app)
        .get('/api/jobs/by-number/12345678')
        .set('Authorization', `Bearer ${workerToken}`);
      jobIdLocal = jobRes.body.id;
      floorId = jobRes.body.floors[0].id;
      populateFloorId = jobRes.body.floors[1].id;

      const wsPopulate = await request(app)
        .post('/api/worksheets')
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ jobId: jobIdLocal });
      expect(wsPopulate.status).toBe(201);
      populateWorksheetId = wsPopulate.body.id;

      const ws1 = await request(app)
        .post('/api/worksheets')
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ jobId: jobIdLocal });
      expect(ws1.status).toBe(201);
      duplicateWs1Id = ws1.body.id;

      const ws2 = await request(app)
        .post('/api/worksheets')
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ jobId: jobIdLocal });
      expect(ws2.status).toBe(201);
      duplicateWs2Id = ws2.body.id;
    });

    afterAll(async () => {
      const seals = await prisma.seal.findMany({
        where: { sealNumber: { startsWith: WS_TEST_PREFIX } },
        select: { id: true },
      });
      if (seals.length > 0) {
        const sealIds = seals.map((s) => s.id);
        await prisma.workSheetItem.deleteMany({ where: { sealId: { in: sealIds } } });
        await prisma.seal.deleteMany({ where: { id: { in: sealIds } } });
      }
    });

    function uniqueSealNumber(suffix) {
      return `${WS_TEST_PREFIX}${String(Date.now()).slice(-7)}${suffix}`;
    }

    async function createSeal(suffix, targetFloorId = floorId) {
      const res = await request(app)
        .post('/api/seals')
        .set('Authorization', `Bearer ${workerToken}`)
        .send(sealBody(jobIdLocal, targetFloorId, uniqueSealNumber(suffix)));
      expect(res.status).toBe(201);
      return res.body;
    }

    it('rejects adding seal entry already on another worksheet', async () => {
      const seal = await createSeal('1');
      const entryId = seal.entries[0].id;

      const first = await request(app)
        .post(`/api/worksheets/${duplicateWs1Id}/items`)
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ sealEntryIds: [entryId] });
      expect(first.status).toBe(201);

      const second = await request(app)
        .post(`/api/worksheets/${duplicateWs2Id}/items`)
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ sealEntryIds: [entryId] });
      expect(second.status).toBe(400);
      expect(second.body.error).toMatch(/jiném soupisu/i);
    });

    it('populate without status filter includes draft and checked seals only', async () => {
      const draftSeal = await createSeal('0', populateFloorId);
      const checkedSeal = await createSeal('1', populateFloorId);
      const invoicedSeal = await createSeal('2', populateFloorId);

      await markSealChecked(app, vedeniToken, workerToken, checkedSeal.id);

      await markSealChecked(app, vedeniToken, workerToken, invoicedSeal.id);
      await prisma.seal.update({
        where: { id: invoicedSeal.id },
        data: { status: 'invoiced' },
      });

      const populate = await request(app)
        .post(`/api/worksheets/${populateWorksheetId}/populate`)
        .set('Authorization', `Bearer ${workerToken}`)
        .send({ floorIds: [populateFloorId] });
      expect(populate.status).toBe(201);

      const addedEntryIds = populate.body.map((item) => item.sealEntryId);
      expect(addedEntryIds).toContain(draftSeal.entries[0].id);
      expect(addedEntryIds).toContain(checkedSeal.entries[0].id);
      expect(addedEntryIds).not.toContain(invoicedSeal.entries[0].id);
    });
  });
});
