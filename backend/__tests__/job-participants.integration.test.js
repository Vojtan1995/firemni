import { describe, it, expect, beforeAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';

describe('Job participants management', () => {
  const app = createApp();
  let workerToken;
  let vedeniToken;
  let jobId;
  let worker2Id;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    vedeniToken = await login('vedeni');
    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;

    const users = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${vedeniToken}`);
    worker2Id = users.body.find((u) => u.username === 'worker2').id;
  });

  it('worker cannot list participants (403)', async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/participants`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('vedeni lists participants with seal counts', async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/participants`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    if (res.body.length > 0) {
      expect(res.body[0]).toHaveProperty('sealCount');
      expect(res.body[0]).toHaveProperty('displayName');
    }
  });

  it('vedeni assigns and removes a worker; reassign keeps it idempotent', async () => {
    const add = await request(app)
      .post(`/api/jobs/${jobId}/participants`)
      .set('Authorization', `Bearer ${vedeniToken}`)
      .send({ userId: worker2Id, roleOnJob: 'worker' });
    expect(add.status).toBe(201);

    const list = await request(app)
      .get(`/api/jobs/${jobId}/participants`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(list.body.some((p) => p.userId === worker2Id)).toBe(true);

    const remove = await request(app)
      .delete(`/api/jobs/${jobId}/participants/${worker2Id}`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(remove.status).toBe(200);

    const after = await request(app)
      .get(`/api/jobs/${jobId}/participants`)
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(after.body.some((p) => p.userId === worker2Id)).toBe(false);
  });
});
