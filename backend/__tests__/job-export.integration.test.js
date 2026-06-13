import sharp from 'sharp';
import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const SEAL_PREFIX = '8840';
const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  'base64',
);

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    system: 'Export test',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    note: 'Veřejná poznámka',
    entries: [
      {
        entryType: 'EL.V.',
        dimension: 'Ø20',
        quantity: 1,
        insulation: 'žádná',
        materials: ['Pěna'],
      },
    ],
  };
}

describe('Job export (task 5.1)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floor1Id;
  let sealId;

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

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floor1Id = jobRes.body.floors[0].id;

    const created = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send(sealBody(jobId, floor1Id, `${SEAL_PREFIX}1`));
    expect(created.status).toBe(201);
    sealId = created.body.id;

    const photo = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${workerToken}`)
      .attach('photo', tinyPng, { filename: 'photo.png', contentType: 'image/png' });
    expect(photo.status).toBe(201);
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: SEAL_PREFIX } } });
    await prisma.$disconnect();
  });

  it('management exports job CSV with sections and BOM', async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/export/csv`)
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/csv/);
    expect(res.text.charCodeAt(0)).toBe(0xfeff);
    expect(res.text).toContain('Export zakázky');
    expect(res.text).toContain('12345678');
    expect(res.text).toContain(`${SEAL_PREFIX}1`);
    expect(res.text).toContain('Export test');
    expect(res.text).toContain('Soupisy práce');
    expect(res.text).toContain('Historie');
  });

  it('management exports job PDF', async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/export/pdf`)
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/application\/pdf/);
    expect(res.body.length).toBeGreaterThan(500);
    expect(res.body.subarray(0, 4).toString()).toBe('%PDF');
  });

  it('worker export is scoped to own seals', async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/export/csv`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(res.text).toContain(`${SEAL_PREFIX}1`);
  });

  it('rejects unknown job', async () => {
    const res = await request(app)
      .get('/api/jobs/00000000-0000-4000-8000-000000000099/export/csv')
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(404);
  });

  it('handles many photos without failing PDF export', async () => {
    const extra = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send(sealBody(jobId, floor1Id, `${SEAL_PREFIX}2`));
    expect(extra.status).toBe(201);

    const webp = await sharp(tinyPng).webp().toBuffer();
    for (let i = 0; i < 5; i++) {
      await request(app)
        .post(`/api/seals/${extra.body.id}/photos`)
        .set('Authorization', `Bearer ${workerToken}`)
        .attach('photo', webp, { filename: `p${i}.webp`, contentType: 'image/webp' });
    }

    const res = await request(app)
      .get(`/api/jobs/${jobId}/export/pdf`)
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.body.subarray(0, 4).toString()).toBe('%PDF');
  });
});
