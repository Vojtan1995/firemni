import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const SEAL_PREFIX = '8860';
const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  'base64',
);
const tinyJpeg = Buffer.from(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA//2Q==',
  'base64',
);

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    system: 'Plan',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
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

describe('Floor drawings and markers (task 5.3)', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let ucetniToken;
  let jobId;
  let floor1Id;
  let floor2Id;
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
    ucetniToken = await login('ucetni');

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floor1Id = jobRes.body.floors[0].id;
    floor2Id = jobRes.body.floors[1]?.id ?? jobRes.body.floors[0].id;

    const created = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send(sealBody(jobId, floor1Id, `${SEAL_PREFIX}1`));
    expect(created.status).toBe(201);
    sealId = created.body.id;
  });

  afterAll(async () => {
    await prisma.sealMarker.deleteMany({
      where: { seal: { sealNumber: { startsWith: SEAL_PREFIX } } },
    });
    await prisma.floorDrawing.deleteMany({
      where: { floorId: floor1Id },
    });
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: SEAL_PREFIX } } });
    await prisma.$disconnect();
  });

  it('vedení can upload floor drawing and preserve original PNG', async () => {
    const res = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set('Authorization', `Bearer ${managementToken}`)
      .attach('drawing', tinyPng, { filename: 'plan.png', contentType: 'image/png' });

    expect(res.status).toBe(201);
    expect(res.body.mimeType).toBe('image/png');
    expect(res.body.width).toBeGreaterThan(0);
    expect(res.body.height).toBeGreaterThan(0);

    const file = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/file`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(file.status).toBe(200);
    expect(file.headers['content-type']).toMatch(/image\/png/);
    expect(Buffer.compare(file.body, tinyPng)).toBe(0);
  });

  it('vedení can upload JPEG floor drawing without WebP conversion', async () => {
    const res = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set('Authorization', `Bearer ${managementToken}`)
      .attach('drawing', tinyJpeg, { filename: 'plan.jpg', contentType: 'image/jpeg' });

    expect(res.status).toBe(201);
    expect(res.body.mimeType).toBe('image/jpeg');

    const file = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/file`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(file.status).toBe(200);
    expect(file.headers['content-type']).toMatch(/image\/jpeg/);
    expect(Buffer.compare(file.body, tinyJpeg)).toBe(0);
  });

  it('worker cannot upload drawing', async () => {
    const res = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set('Authorization', `Bearer ${workerToken}`)
      .attach('drawing', tinyPng, { filename: 'plan.png', contentType: 'image/png' });

    expect(res.status).toBe(403);
  });

  it('ucetni can upload and delete floor drawing', async () => {
    const upload = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor2Id}/drawing`)
      .set('Authorization', `Bearer ${ucetniToken}`)
      .attach('drawing', tinyPng, { filename: 'plan.png', contentType: 'image/png' });

    expect(upload.status).toBe(201);

    const del = await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor2Id}/drawing`)
      .set('Authorization', `Bearer ${ucetniToken}`);

    expect(del.status).toBe(200);
    expect(del.body.ok).toBe(true);
  });

  it('floors list includes hasDrawing flag', async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/floors`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(res.body.length).toBeGreaterThan(0);
    expect(typeof res.body[0].hasDrawing).toBe('boolean');
    expect(res.body.some((f) => f.hasDrawing === true)).toBe(true);
  });

  it('export pdf accepts sealIds and reviewStatus filters', async () => {
    const bySeal = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/export/pdf`)
      .query({ sealIds: sealId })
      .set('Authorization', `Bearer ${managementToken}`);

    expect(bySeal.status).toBe(200);
    expect(bySeal.headers['content-type']).toMatch(/application\/pdf/);

    const byReview = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/export/pdf`)
      .query({ reviewStatus: 'returned' })
      .set('Authorization', `Bearer ${managementToken}`);

    expect(byReview.status).toBe(200);
    expect(byReview.headers['content-type']).toMatch(/application\/pdf/);
  });

  it('returns drawing bundle with file endpoint', async () => {
    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(bundle.status).toBe(200);
    expect(bundle.body.drawing).toBeTruthy();

    const file = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/file`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(file.status).toBe(200);
    expect(file.headers['content-type']).toMatch(/image\/(png|jpeg|webp)/);
  });

  it('worker can place and read seal marker', async () => {
    const put = await request(app)
      .put(`/api/jobs/${jobId}/floors/${floor1Id}/markers/${sealId}`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ x: 0.42, y: 0.58 });

    expect(put.status).toBe(200);
    expect(put.body.x).toBeCloseTo(0.42);
    expect(put.body.y).toBeCloseTo(0.58);

    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set('Authorization', `Bearer ${managementToken}`);

    expect(bundle.body.markers).toHaveLength(1);
    expect(bundle.body.markers[0].sealNumber).toBe(`${SEAL_PREFIX}1`);
    expect(bundle.body.markers[0].createdById).toBeTruthy();
    expect(bundle.body.markers[0].createdByName).toBeTruthy();
  });

  it('sync pull includes drawings and markers', async () => {
    const res = await request(app)
      .get('/api/sync/pull')
      .set('Authorization', `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.floorDrawings)).toBe(true);
    expect(Array.isArray(res.body.sealMarkers)).toBe(true);
    expect(res.body.sealMarkers.some((m) => m.sealId === sealId)).toBe(true);
  });

  it('returns next seal number and placement stats', async () => {
    const next = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/next-seal-number`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(next.status).toBe(200);
    expect(Number.parseInt(next.body.nextSealNumber, 10)).toBeGreaterThan(
      Number.parseInt(`${SEAL_PREFIX}1`, 10),
    );

    const stats = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/placement-stats`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(stats.status).toBe(200);
    expect(stats.body.total).toBeGreaterThanOrEqual(1);
    expect(stats.body.placed).toBeGreaterThanOrEqual(1);
    expect(stats.body.unplaced).toBeGreaterThanOrEqual(0);
  });

  it('seal detail includes marker coordinates', async () => {
    const res = await request(app)
      .get(`/api/seals/${sealId}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.marker).toBeTruthy();
    expect(res.body.marker.x).toBeCloseTo(0.42);
    expect(res.body.marker.y).toBeCloseTo(0.58);
  });

  it('sync push accepts seal_marker update', async () => {
    const mutationId = crypto.randomUUID();
    const res = await request(app)
      .post('/api/sync/push')
      .set('Authorization', `Bearer ${workerToken}`)
      .send({
        mutations: [
          {
            mutationId,
            deviceId: 'test-device',
            entityType: 'seal_marker',
            operation: 'update',
            payload: { sealId, floorId: floor1Id, x: 0.1, y: 0.2 },
          },
        ],
      });

    expect(res.status).toBe(200);
    expect(res.body.results[0].status).toBe('ok');
  });

  it('vedení can delete marker and drawing', async () => {
    const delMarker = await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor1Id}/markers/${sealId}`)
      .set('Authorization', `Bearer ${managementToken}`);
    expect(delMarker.status).toBe(200);

    const delDrawing = await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set('Authorization', `Bearer ${managementToken}`);
    expect(delDrawing.status).toBe(200);
    expect(delDrawing.body.ok).toBe(true);

    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(bundle.body.drawing).toBeNull();
  });
});
