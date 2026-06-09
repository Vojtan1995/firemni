import request from 'supertest';

export const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  'base64',
);

export async function addSealPhoto(app, token, sealId) {
  const res = await request(app)
    .post(`/api/seals/${sealId}/photos`)
    .set('Authorization', `Bearer ${token}`)
    .attach('photo', tinyPng, { filename: 'photo.png', contentType: 'image/png' });
  expect(res.status).toBe(201);
  return res.body;
}

export async function markSealChecked(app, managementToken, workerToken, sealId) {
  await addSealPhoto(app, workerToken, sealId);
  const res = await request(app)
    .patch(`/api/seals/${sealId}/status`)
    .set('Authorization', `Bearer ${managementToken}`)
    .send({ status: 'checked' });
  expect(res.status).toBe(200);
  return res.body;
}
