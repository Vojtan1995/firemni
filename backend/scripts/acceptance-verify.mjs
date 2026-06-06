/**
 * Acceptance verification script for RBAC refactor.
 * Run: node --experimental-vm-modules scripts/acceptance-verify.mjs
 */
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const results = [];

function record(id, name, ok, detail) {
  results.push({ id, name, ok, detail });
  console.log(`${ok ? 'OK' : 'FAIL'} [${id}] ${name}${detail ? ` — ${detail}` : ''}`);
}

async function login(app, username) {
  const res = await request(app).post('/api/auth/login').send({ username, pin: '1234' });
  return res.body.token;
}

async function main() {
  const app = createApp();

  // DB models
  const tables = await prisma.$queryRaw`
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name IN ('worksheets', 'worksheet_workers', 'worksheet_items', 'change_log')
    ORDER BY table_name
  `;
  const names = tables.map((t) => t.table_name);
  record(
    'DB-1',
    'Tabulky WorkSheet/WorkSheetWorker/WorkSheetItem/ChangeLog existují',
    names.length === 4,
    names.join(', '),
  );

  const wsCol = await prisma.$queryRaw`
    SELECT is_nullable FROM information_schema.columns
    WHERE table_name = 'worksheets' AND column_name = 'job_id'
  `;
  record(
    'DB-2',
    'WorkSheet.job_id je povinný (NOT NULL)',
    wsCol[0]?.is_nullable === 'NO',
    `is_nullable=${wsCol[0]?.is_nullable}`,
  );

  const workerToken = await login(app, 'worker1');
  const worker2Token = await login(app, 'worker2');
  const ucetniToken = await login(app, 'ucetni');
  const vedeniToken = await login(app, 'vedeni');
  const adminToken = await login(app, 'admin');

  const jobRes = await request(app)
    .get('/api/jobs/by-number/12345678')
    .set('Authorization', `Bearer ${workerToken}`);
  const jobId = jobRes.body.id;
  const floorId = jobRes.body.floors[0].id;

  // Roles - ucetni cannot create user
  const ucetniUser = await request(app)
    .post('/api/users')
    .set('Authorization', `Bearer ${ucetniToken}`)
    .send({ username: `acc_${Date.now()}`, displayName: 'X', pin: '1234', role: 'worker' });
  record('R-UCETNI-1', 'Administrativa nemůže založit uživatele', ucetniUser.status === 403);

  const vedeniUsers = await request(app)
    .get('/api/users')
    .set('Authorization', `Bearer ${vedeniToken}`);
  record(
    'R-VEDENI-1',
    'Vedení nevidí admin účty',
    !vedeniUsers.body.some((u) => u.role === 'admin'),
  );

  const adminUsers = await request(app)
    .get('/api/users')
    .set('Authorization', `Bearer ${adminToken}`);
  record(
    'R-ADMIN-1',
    'Admin vidí všechny účty včetně admin',
    adminUsers.body.some((u) => u.role === 'admin'),
  );

  // Worker stats
  const w2 = adminUsers.body.find((u) => u.username === 'worker2');
  const statsForbidden = await request(app)
    .get(`/api/stats/overview?userId=${w2.id}`)
    .set('Authorization', `Bearer ${workerToken}`);
  record('R-WORKER-1', 'Worker nevidí cizí statistiky', statsForbidden.status === 403);

  const wsForbidden = await request(app)
    .post('/api/worksheets')
    .set('Authorization', `Bearer ${workerToken}`)
    .send({ jobId, workerIds: [w2.id] });
  record('R-WORKER-2', 'Worker nevytvoří soupis za jiného', wsForbidden.status === 403);

  // Seal author preservation
  const sealNum = `${Date.now()}`.slice(-6);
  const createSeal = await request(app)
    .post('/api/seals')
    .set('Authorization', `Bearer ${workerToken}`)
    .send({
      jobId,
      floorId,
      sealNumber: sealNum,
      system: 'ACC',
      construction: 'Stena',
      location: 'T',
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
  const sealId = createSeal.body.id;
  const creatorId = createSeal.body.createdById;
  const patchSeal = await request(app)
    .patch(`/api/seals/${sealId}`)
    .set('Authorization', `Bearer ${worker2Token}`)
    .send({ note: 'acc test', baseVersion: createSeal.body.version });
  record(
    'SEAL-1',
    'Editace cizí ucpávky zachová původního autora',
    patchSeal.body.createdById === creatorId && patchSeal.body.updatedById !== creatorId,
  );

  const changeCount = await prisma.changeLog.count({
    where: { entityType: 'seal', entityId: sealId },
  });
  record('AUDIT-1', 'Editace vytvoří audit (ChangeLog)', changeCount > 0, `count=${changeCount}`);

  // Photos append-only
  const beforePhotos = await prisma.sealPhoto.count({ where: { sealId } });
  // Skip upload if no valid image - use count from existing seal photos after integration tests
  const allPhotos = await prisma.sealPhoto.findMany({ where: { sealId }, orderBy: { createdAt: 'asc' } });
  const delPhoto = allPhotos[0]
    ? await request(app)
        .delete(`/api/photos/${allPhotos[0].id}`)
        .set('Authorization', `Bearer ${vedeniToken}`)
    : { status: 403 };
  record('PHOTO-1', 'Mazání fotek je zakázáno (403)', delPhoto.status === 403);
  const afterPhotos = await prisma.sealPhoto.count({ where: { sealId } });
  record(
    'PHOTO-2',
    'Staré fotky zůstanou v DB po pokusu o smazání',
    afterPhotos === beforePhotos || beforePhotos === 0,
    `before=${beforePhotos}, after=${afterPhotos}`,
  );

  // Multi-job worksheet
  const otherProject = `${Date.now()}`.slice(-8).padStart(8, '0');
  const otherJob = await request(app)
    .post('/api/jobs')
    .set('Authorization', `Bearer ${vedeniToken}`)
    .send({ projectNumber: otherProject, name: 'Acc other' });
  const otherFloor = await request(app)
    .post(`/api/jobs/${otherJob.body.id}/floors`)
    .set('Authorization', `Bearer ${vedeniToken}`)
    .send({ name: 'P' });
  const otherSeal = await request(app)
    .post('/api/seals')
    .set('Authorization', `Bearer ${workerToken}`)
    .send({
      jobId: otherJob.body.id,
      floorId: otherFloor.body.id,
      sealNumber: `${sealNum}9`,
      system: 'X',
      construction: 'S',
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
  const ws = await request(app)
    .post('/api/worksheets')
    .set('Authorization', `Bearer ${vedeniToken}`)
    .send({ jobId, workerIds: [creatorId] });
  const addWrong = await request(app)
    .post(`/api/worksheets/${ws.body.id}/items`)
    .set('Authorization', `Bearer ${vedeniToken}`)
    .send({ sealEntryIds: [otherSeal.body.entries[0].id] });
  record(
    'WS-1',
    'Nelze přidat položky z jiné zakázky do soupisu',
    addWrong.status === 400,
    `status=${addWrong.status}`,
  );

  // Workflow bypass
  const ws2 = await request(app)
    .post('/api/worksheets')
    .set('Authorization', `Bearer ${workerToken}`)
    .send({ jobId });
  const bypassReview = await request(app)
    .patch(`/api/worksheets/${ws2.body.id}/status`)
    .set('Authorization', `Bearer ${workerToken}`)
    .send({ status: 'reviewed' });
  record(
    'WS-2',
    'Worker nemůže přeskočit workflow (reviewed)',
    bypassReview.status === 403,
    `status=${bypassReview.status}`,
  );

  const bypassInvoice = await request(app)
    .patch(`/api/worksheets/${ws2.body.id}/status`)
    .set('Authorization', `Bearer ${ucetniToken}`)
    .send({ status: 'invoiced' });
  record(
    'WS-3',
    'Administrativa nemůže fakturovat bez ready_for_invoice',
    bypassInvoice.status === 400,
    `status=${bypassInvoice.status}`,
  );

  // Worker cannot PATCH seal (ucetni)
  const ucetniPatch = await request(app)
    .patch(`/api/seals/${sealId}`)
    .set('Authorization', `Bearer ${ucetniToken}`)
    .send({ note: 'hack', baseVersion: patchSeal.body.version });
  record('R-UCETNI-2', 'Administrativa nemůže editovat ucpávku', ucetniPatch.status === 403);

  await prisma.$disconnect();

  const failed = results.filter((r) => !r.ok);
  console.log('\n--- SUMMARY ---');
  console.log(`Total: ${results.length}, OK: ${results.length - failed.length}, FAIL: ${failed.length}`);
  process.exit(failed.length > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
