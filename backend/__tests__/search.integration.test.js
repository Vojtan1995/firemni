import { describe, it, expect, beforeAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';

describe('Search API', () => {
  const app = createApp();
  let workerToken;
  let vedeniToken;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login('worker1');
    vedeniToken = await login('vedeni');
  });

  it('rejects empty query without filters', async () => {
    const res = await request(app)
      .get('/api/search')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(400);
  });

  it('worker finds demo job by project number', async () => {
    const res = await request(app)
      .get('/api/search?q=12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.items.some((i) => i.type === 'job')).toBe(true);
  });

  it('vedeni can filter returned seals', async () => {
    const res = await request(app)
      .get('/api/search?filters=awaiting_review&limit=5')
      .set('Authorization', `Bearer ${vedeniToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.items)).toBe(true);
  });
});
