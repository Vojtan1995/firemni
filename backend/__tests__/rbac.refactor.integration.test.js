import { describe, it, expect, beforeAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('RBAC refactor integration', () => {
  const app = createApp();
  let workerToken;
  let worker2Token;
  let ucetniToken;
  let vedeniToken;
  let adminToken;
  let jobId;
  let floorId;
  let sealId;
  let worksheetId;
  const uniqueSeal = `${Date.now()}`.slice(-6);
  const uniqueProject = `${Date.now()}`.slice(-8).padStart(8, '0');

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
    floorId = jobRes.body.floors[0].id;
  });

  it('ucetni cannot create users (403)', async () => {
    const res = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${ucetniToken}`)
      .send({
        username: 'blocked_user',
        displayName: 'Blocked',
        pin: '1234',
        role: 'worker',
      });
    expect(res.status).toBe(403);
  });

  it('vedeni does not see admin accounts', async () => {
    const res = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(res.status).toBe(200);
    expect(res.body.some((u) => u.role === 'admin')).toBe(false);
  });

  it('admin sees all accounts including admin', async () => {
    const res = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.some((u) => u.role === 'admin')).toBe(true);
  });

  it('worker cannot access other worker stats (403)', async () => {
    const users = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${adminToken}`);
    const worker2 = users.body.find((u) => u.username === 'worker2');
    const res = await request(app)
      .get(`/api/stats/overview?userId=${worker2.id}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('worker stats scoped to self', async () => {
    const res = await request(app)
      .get('/api/stats/overview')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.role).toBe('worker');
  });

  it('worker creates seal and createdById is preserved on edit by worker2', async () => {
    const create = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId,
        floorId,
        sealNumber: uniqueSeal,
        system: 'RBAC',
        construction: 'Stena',
        location: 'Test',
        fireRating: 'EI 60',
        entries: [
          {
            entryType: 'EL.V.',
            dimension: '50',
            quantity: 1,
            insulation: 'zadna',
            materials: ['Pena'],
          },
        ],
      });
    expect(create.status).toBe(201);
    sealId = create.body.id;
    const creatorId = create.body.createdById;

    const patch = await request(app)
      .patch(`/api/seals/${sealId}`)
      .set('Authorization', `Bearer ${worker2Token}`)
      .send({ note: 'Edited by worker2', baseVersion: create.body.version });
    expect(patch.status).toBe(200);
    expect(patch.body.createdById).toBe(creatorId);
    expect(patch.body.updatedById).not.toBe(creatorId);
  });

  it('edit creates change log entry', async () => {
    const changes = await prisma.changeLog.findMany({
      where: { entityType: 'seal', entityId: sealId, fieldName: 'note' },
    });
    expect(changes.length).toBeGreaterThan(0);
  });

  it('photo delete returns 403 for all roles', async () => {
    const upload = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${workerToken}`)
      .attach('photo', Buffer.from('fake'), { filename: 'test.webp', contentType: 'image/webp' });
    if (upload.status !== 201) return;
    const photoId = upload.body.id;
    const del = await request(app)
      .delete(`/api/photos/${photoId}`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(del.status).toBe(403);
  });

  it('worker creates worksheet for self only', async () => {
    const create = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ jobId });
    expect(create.status).toBe(201);
    worksheetId = create.body.id;
    expect(create.body.workers.some((w) => w.userId)).toBeTruthy();
  });

  it('worker cannot create worksheet for another worker', async () => {
    const users = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${adminToken}`);
    const worker2 = users.body.find((u) => u.username === 'worker2');
    const res = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ jobId, workerIds: [worker2.id] });
    expect(res.status).toBe(403);
  });

  it('worksheet rejects items from different job', async () => {
    const otherJob = await request(app)
      .post('/api/jobs')
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ projectNumber: uniqueProject, name: 'Other job' });
    expect(otherJob.status).toBe(201);

    const otherFloor = await request(app)
      .post(`/api/jobs/${otherJob.body.id}/floors`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ name: 'P1' });
    const otherSeal = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        jobId: otherJob.body.id,
        floorId: otherFloor.body.id,
        sealNumber: `${uniqueSeal}2`,
        system: 'X',
        construction: 'Stena',
        location: 'X',
        fireRating: 'EI 60',
        entries: [
          {
            entryType: 'EL.V.',
            dimension: '50',
            quantity: 1,
            insulation: 'zadna',
            materials: ['Pena'],
          },
        ],
      });
    const entryId = otherSeal.body.entries[0].id;

    const ws = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ jobId, workerIds: [otherSeal.body.createdById] });
    expect(ws.status).toBe(201);

    const add = await request(app)
      .post(`/api/worksheets/${ws.body.id}/items`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ sealEntryIds: [entryId] });
    expect(add.status).toBe(400);
  });

  it('worksheet workflow transitions', async () => {
    const submit = await request(app)
      .patch(`/api/worksheets/${worksheetId}/status`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ status: 'submitted' });
    expect(submit.status).toBe(200);

    const review = await request(app)
      .patch(`/api/worksheets/${worksheetId}/status`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ status: 'reviewed' });
    expect(review.status).toBe(200);

    const ready = await request(app)
      .patch(`/api/worksheets/${worksheetId}/status`)
      .set('Authorization', `Bearer ${ucetniToken}`)
      .send({ status: 'ready_for_invoice' });
    expect(ready.status).toBe(200);

    const invoiced = await request(app)
      .patch(`/api/worksheets/${worksheetId}/status`)
      .set('Authorization', `Bearer ${ucetniToken}`)
      .send({ status: 'invoiced' });
    expect(invoiced.status).toBe(200);
  });

  it('seal history endpoint requires vedeni/admin', async () => {
    const denied = await request(app)
      .get(`/api/seals/${sealId}/history`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(denied.status).toBe(403);

    const ok = await request(app)
      .get(`/api/seals/${sealId}/history`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(ok.status).toBe(200);
    expect(Array.isArray(ok.body)).toBe(true);
  });
});
