import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const PREFIX = '7788';

describe('Worksheet export per PDF template — Task 9', () => {
  const app = createApp();
  let token;
  let jobId;
  let floor1;
  let floor2;
  let worksheetId;

  async function login(username) {
    const res = await request(app).post('/api/auth/login').send({ username, pin: '123456' });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  async function createSealEntry(sealNumber, floorId) {
    const res = await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${token}`)
      .send({
        jobId,
        floorId,
        sealNumber,
        trade: 'elektrikari',
        system: 'Intuseal',
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
            materials: ['INTU FR'],
          },
        ],
      });
    expect(res.status).toBe(201);
    return res.body.entries[0].id;
  }

  beforeAll(async () => {
    token = await login('vedeni');
    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${token}`);
    jobId = jobRes.body.id;
    floor1 = jobRes.body.floors[0].id;
    floor2 = jobRes.body.floors[1].id;
    const me = await prisma.user.findUnique({ where: { username: 'vedeni' } });

    const e1 = await createSealEntry(`${PREFIX}1`, floor1);
    const e2 = await createSealEntry(`${PREFIX}2`, floor2);

    const ws = await request(app)
      .post('/api/worksheets')
      .set('Authorization', `Bearer ${token}`)
      .send({ jobId, workerIds: [me.id] });
    expect(ws.status).toBe(201);
    worksheetId = ws.body.id;
    const add = await request(app)
      .post(`/api/worksheets/${worksheetId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ sealEntryIds: [e1, e2] });
    expect(add.status).toBe(201);
  });

  afterAll(async () => {
    await prisma.workSheetItem.deleteMany({ where: { sealNumber: { startsWith: PREFIX } } });
    await prisma.seal.deleteMany({ where: { sealNumber: { startsWith: PREFIX } } });
  });

  it('CSV has all required columns including Řemeslo, in order', async () => {
    const res = await request(app)
      .get(`/api/worksheets/${worksheetId}/export/csv`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const text = res.text;
    const header = text.split('\n')[0];
    for (const col of [
      'Podlaží',
      'Prostup',
      'Řemeslo',
      'Systém',
      'Katalog ID',
      'Typ',
      'Rozměr',
      'Počet',
      'Izolace',
      'Umístění v PÚ',
      'Provedl',
      'Jednotková cena',
      'Cena celkem',
    ]) {
      expect(header).toContain(col);
    }
    // Řemeslo column comes before Systém (template order).
    expect(header.indexOf('Řemeslo')).toBeLessThan(header.indexOf('Systém'));
  });

  it('CSV groups by floor with per-floor totals and a grand total without VAT', async () => {
    const res = await request(app)
      .get(`/api/worksheets/${worksheetId}/export/csv`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const text = res.text;
    const perFloorCount = (text.match(/Cena za podlaží/g) || []).length;
    expect(perFloorCount).toBe(2); // two floors
    expect(text).toContain('Cena celkem bez DPH');
    expect(text).toContain('Datum');
  });

  it('PDF export returns a non-empty application/pdf', async () => {
    const res = await request(app)
      .get(`/api/worksheets/${worksheetId}/export/pdf`)
      .set('Authorization', `Bearer ${token}`)
      .buffer(true)
      .parse((r, cb) => {
        const chunks = [];
        r.on('data', (c) => chunks.push(c));
        r.on('end', () => cb(null, Buffer.concat(chunks)));
      });
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('application/pdf');
    expect(res.body.length).toBeGreaterThan(1000);
    // PDF magic header
    expect(res.body.slice(0, 4).toString()).toBe('%PDF');
  });
});
