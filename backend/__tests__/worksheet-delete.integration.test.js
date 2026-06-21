import { describe, it, expect, beforeAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';

describe('Worksheet delete (draft only)', () => {
  const app = createApp();
  let workerToken;
  let worker2Token;
  let vedeniToken;
  let adminToken;
  let jobId;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function createDraft(token) {
    const res = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${token}`)
      .send({ jobId });
    expect(res.status).toBe(201);
    return res.body.id;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    worker2Token = await login('worker2');
    vedeniToken = await login('vedeni');
    adminToken = await login('admin');
    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
  });

  it('worker can delete own draft worksheet', async () => {
    const id = await createDraft(workerToken);
    const del = await request(app)
      .delete(`/api/worksheets/${id}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(del.status).toBe(200);

    const detail = await request(app)
      .get(`/api/worksheets/${id}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(detail.status).toBe(404);
  });

  it('worker cannot delete another worker draft (403)', async () => {
    const id = await createDraft(worker2Token);
    const del = await request(app)
      .delete(`/api/worksheets/${id}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(del.status).toBe(403);
  });

  it('cannot delete a non-draft worksheet (400)', async () => {
    const id = await createDraft(workerToken);
    const submit = await request(app)
      .patch(`/api/worksheets/${id}/status`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ status: 'submitted' });
    expect(submit.status).toBe(200);

    const del = await request(app)
      .delete(`/api/worksheets/${id}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(del.status).toBe(400);
    expect(del.body.error).toMatch(/rozpracovaný/i);
  });

  it('vedeni can delete any draft worksheet', async () => {
    const id = await createDraft(worker2Token);
    const del = await request(app)
      .delete(`/api/worksheets/${id}`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(del.status).toBe(200);
  });

  it('admin can delete any draft worksheet', async () => {
    const id = await createDraft(worker2Token);
    const del = await request(app)
      .delete(`/api/worksheets/${id}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(del.status).toBe(200);
  });

  it('deleted draft no longer appears in list', async () => {
    const id = await createDraft(workerToken);
    await request(app)
      .delete(`/api/worksheets/${id}`)
      .set('Authorization', `Bearer ${workerToken}`);
    const list = await request(app)
      .get('/api/worksheets')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(list.status).toBe(200);
    expect(list.body.some((ws) => ws.id === id)).toBe(false);
  });
});
