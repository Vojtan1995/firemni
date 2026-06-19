import sharp from 'sharp';
import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';
import { getObjectStorage } from '../dist/services/storage.service.js';

const PHOTO_PREFIX = '9977';
const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  'base64',
);
let tinyWebp;

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: 'elektrikari',
    system: 'Photo test',
    construction: 'Stena',
    location: 'Chodba',
    fireRating: 'EI 60',
    entries: [
      {
        entryType: 'EL.V.',
        electroInstallationType: 'Svazek',
        dimension: '50',
        quantity: 1,
        insulation: 'zadna',
        materials: ['Pena'],
      },
    ],
  };
}

describe('Photos upload integration', () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floorId;
  let sealId;
  let photoId;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    tinyWebp = await sharp(tinyPng).webp({ quality: 85 }).toBuffer();
    workerToken = await login('worker1');
    managementToken = await login('vedeni');

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(jobRes.status).toBe(200);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;

    const sealRes = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${workerToken}`)
      .send(sealBody(jobId, floorId, `${PHOTO_PREFIX}1`));
    expect(sealRes.status).toBe(201);
    sealId = sealRes.body.id;
  });

  afterAll(async () => {
    const photos = await prisma.sealPhoto.findMany({
      where: { seal: { sealNumber: { startsWith: PHOTO_PREFIX } } },
    });
    for (const photo of photos) {
      await getObjectStorage().delete(photo.filePath);
    }
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: PHOTO_PREFIX } } });
    await prisma.$disconnect();
  });

  it('worker can upload a supported image to a draft seal', async () => {
    const res = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${workerToken}`)
      .attach('photo', tinyPng, { filename: 'photo.png', contentType: 'image/png' });

    expect(res.status).toBe(201);
    expect(res.body.mimeType).toBe('image/webp');
    expect(res.body.filePath).toMatch(/\.webp$/);
    expect(res.body.url).toBe(`/uploads/${res.body.filePath}`);
    photoId = res.body.id;

    const stored = await prisma.sealPhoto.findUnique({ where: { id: photoId } });
    expect(stored).toBeTruthy();
    expect(await getObjectStorage().exists(stored.filePath)).toBe(true);
  });

  it('worker cannot delete uploaded photos', async () => {
    const res = await request(app)
      .delete(`/api/photos/${photoId}`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(res.status).toBe(403);
    expect(res.body.code).toBe('FORBIDDEN');
  });

  it('requires auth for photo file download', async () => {
    const res = await request(app).get(`/api/photos/${photoId}/file`);

    expect(res.status).toBe(401);
    expect(res.body.code).toBe('UNAUTHORIZED');
  });

  it('authorized user can download photo file', async () => {
    const res = await request(app)
      .get(`/api/photos/${photoId}/file`)
      .set('Authorization', `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/image\/webp/);
    expect(res.body.length).toBeGreaterThan(0);
  });

  it('accepts application/octet-stream when filename has image extension', async () => {
    const res = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${workerToken}`)
      .attach('photo', tinyPng, {
        filename: 'photo.png',
        contentType: 'application/octet-stream',
      });

    expect(res.status).toBe(201);
    expect(res.body.mimeType).toBe('image/webp');
  });

  it('accepts real webp upload and stores webp output', async () => {
    const res = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${workerToken}`)
      .attach('photo', tinyWebp, {
        filename: 'photo.webp',
        contentType: 'image/webp',
      });

    expect(res.status).toBe(201);
    expect(res.body.mimeType).toBe('image/webp');
    expect(res.body.filePath).toMatch(/\.webp$/);
  });

  it('returns clear error when photo field is missing', async () => {
    const res = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ photoType: 'detail' });

    expect(res.status).toBe(400);
    expect(res.body.code).toBe('BAD_REQUEST');
    expect(res.body.error).toMatch(/photo/i);
  });

  it('rejects unsupported upload MIME type with 400', async () => {
    const res = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${managementToken}`)
      .attach('photo', Buffer.from('not an image'), {
        filename: 'photo.txt',
        contentType: 'text/plain',
      });

    expect(res.status).toBe(400);
    expect(res.body.code).toBe('BAD_REQUEST');
  });

  it('rejects invalid image content with 400 and does not create DB metadata', async () => {
    const before = await prisma.sealPhoto.count({ where: { sealId } });
    const res = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${managementToken}`)
      .attach('photo', Buffer.from('not a png image'), {
        filename: 'fake.png',
        contentType: 'image/png',
      });
    const after = await prisma.sealPhoto.count({ where: { sealId } });

    expect(res.status).toBe(400);
    expect(res.body.code).toBe('BAD_REQUEST');
    expect(after).toBe(before);
  });

  it('rejects oversized uploads with 413', async () => {
    const oversized = Buffer.alloc(16 * 1024 * 1024, 1);
    const res = await request(app)
      .post(`/api/seals/${sealId}/photos`)
      .set('Authorization', `Bearer ${managementToken}`)
      .attach('photo', oversized, {
        filename: 'large.png',
        contentType: 'image/png',
      });

    expect(res.status).toBe(413);
    expect(res.body.code).toBe('UPLOAD_TOO_LARGE');
  });
});
