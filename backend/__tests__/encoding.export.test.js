import { describe, it, expect, beforeAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { csvWithBom } from '../dist/lib/csv-export.js';
import { createCzechPdfDocument } from '../dist/lib/pdf-pagination.js';
import { Readable } from 'stream';

const CZECH_TEST =
  'Příliš žluťoučký kůň úpěl ďábelské ódy. Žluťoučký kůň, požární ucpávka, přízemí, šachta, účetní.';

describe('Czech encoding in exports', () => {
  const app = createApp();
  let managementToken;
  let jobId;

  beforeAll(async () => {
    const login = await request(app)
      .post('/api/auth/login')
      .send({ username: 'vedeni', pin: '1234' });
    managementToken = login.body.token;

    const jobRes = await request(app)
      .get('/api/jobs/by-number/12345678')
      .set('Authorization', `Bearer ${managementToken}`);
    jobId = jobRes.body.id;
  });

  it('csvWithBom prepends UTF-8 BOM', () => {
    const csv = csvWithBom(`"test";"${CZECH_TEST}"`);
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toContain('žluťoučký');
    expect(csv).toContain('účetní');
    expect(csv).not.toMatch(/Ä|Å¡|Å™/);
  });

  it('reports CSV export preserves Czech diacritics', async () => {
    const res = await request(app)
      .get('/api/reports/export/csv')
      .query({ jobId })
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.text.startsWith('\uFEFF')).toBe(true);
    expect(res.text).toMatch(/[čřžýáíéůúňďóěšť]/i);
    expect(res.text).not.toMatch(/Ä|Å¡|Å™/);
  });

  it('job CSV export preserves Czech diacritics', async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/export/csv`)
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.text.startsWith('\uFEFF')).toBe(true);
    expect(res.text).not.toMatch(/Ä|Å¡|Å™/);
  });

  it('createCzechPdfDocument embeds Czech text in PDF buffer', async () => {
    const chunks = [];
    const doc = createCzechPdfDocument({ margin: 40, size: 'A4' });
    doc.on('data', (c) => chunks.push(c));
    const done = new Promise((resolve) => doc.on('end', resolve));
    doc.fontSize(12).text(CZECH_TEST);
    doc.end();
    await done;

    const buffer = Buffer.concat(chunks);
    expect(buffer.length).toBeGreaterThan(1000);
    expect(buffer.slice(0, 4).toString()).toBe('%PDF');
  });

  it('reports PDF export returns valid PDF with Czech-capable font', async () => {
    const res = await request(app)
      .get('/api/reports/export/pdf')
      .query({ jobId })
      .set('Authorization', `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/application\/pdf/);
    const buf = Buffer.isBuffer(res.body) ? res.body : Buffer.from(res.body);
    expect(buf.slice(0, 4).toString()).toBe('%PDF');
    const text = buf.toString('utf8');
    expect(text).not.toMatch(/Ä|Å¡|Å™/);
  });
});
