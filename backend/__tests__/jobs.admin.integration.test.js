import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('Jobs and floors admin (management)', () => {
  const app = createApp();
  let managementToken;
  let workerToken;
  let adminJobId;
  let adminFloorId;

  beforeAll(async () => {
    const mgmt = await request(app)
      .post('/api/auth/login')
      .send({ username: 'vedeni', pin: '123456' });
    managementToken = mgmt.body.token;

    const worker = await request(app)
      .post('/api/auth/login')
      .send({ username: 'worker1', pin: '123456' });
    workerToken = worker.body.token;

    const adminJobNumber = `7${Date.now().toString().slice(-7)}`;
    const jobRes = await request(app)
      .post('/api/jobs')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ projectNumber: adminJobNumber, name: 'Admin test stavba' });
    expect(jobRes.status).toBe(201);
    adminJobId = jobRes.body.id;

    const floorRes = await request(app)
      .post(`/api/jobs/${adminJobId}/floors`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ name: 'Admin test patro' });
    expect(floorRes.status).toBe(201);
    adminFloorId = floorRes.body.id;
  });

  afterAll(async () => {
    if (adminJobId) {
      await prisma.seal.deleteMany({ where: { jobId: adminJobId } });
      await prisma.jobFloor.deleteMany({ where: { jobId: adminJobId } });
      await prisma.job.deleteMany({ where: { id: adminJobId } });
    }
    await prisma.$disconnect();
  });

  it('worker cannot PATCH job', async () => {
    const res = await request(app)
      .patch(`/api/jobs/${adminJobId}`)
      .set('Authorization', `Bearer ${workerToken}`)
      .send({ name: 'X' });
    expect(res.status).toBe(403);
  });

  it('management can PATCH job name', async () => {
    const res = await request(app)
      .patch(`/api/jobs/${adminJobId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ name: 'Testovací stavba' });
    expect(res.status).toBe(200);
    expect(res.body.name).toBe('Testovací stavba');
  });

  it('management can archive and unarchive job', async () => {
    const archived = await request(app)
      .patch(`/api/jobs/${adminJobId}/archive`)
      .set('Authorization', `Bearer ${managementToken}`);
    expect(archived.status).toBe(200);
    expect(archived.body.status).toBe('archived');
    expect(archived.body.isArchived).toBe(true);

    const unarchived = await request(app)
      .patch(`/api/jobs/${adminJobId}/activate`)
      .set('Authorization', `Bearer ${managementToken}`);
    expect(unarchived.status).toBe(200);
    expect(unarchived.body.status).toBe('active');
    expect(unarchived.body.isArchived).toBe(false);
  });

  it('completed job is hidden from worker my jobs', async () => {
    const vedeniUser = await prisma.user.findUnique({ where: { username: 'vedeni' } });
    const workerUser = await prisma.user.findUnique({ where: { username: 'worker1' } });
    await prisma.jobParticipant.upsert({
      where: { jobId_userId: { jobId: adminJobId, userId: workerUser.id } },
      create: {
        jobId: adminJobId,
        userId: workerUser.id,
        roleOnJob: 'worker',
        assignedById: vedeniUser.id,
      },
      update: { lastActivityAt: new Date() },
    });

    const before = await request(app)
      .get('/api/jobs/my')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(before.body.some((j) => j.id === adminJobId)).toBe(true);

    await request(app)
      .patch(`/api/jobs/${adminJobId}/complete`)
      .set('Authorization', `Bearer ${managementToken}`);

    const after = await request(app)
      .get('/api/jobs/my')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(after.body.some((j) => j.id === adminJobId)).toBe(false);

    await request(app)
      .patch(`/api/jobs/${adminJobId}/activate`)
      .set('Authorization', `Bearer ${managementToken}`);
    await prisma.jobParticipant.deleteMany({
      where: { jobId: adminJobId, userId: workerUser.id },
    });
  });

  it('management can PATCH floor name', async () => {
    const res = await request(app)
      .patch(`/api/jobs/${adminJobId}/floors/${adminFloorId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ name: '1. NP upraveno' });
    expect(res.status).toBe(200);
    expect(res.body.name).toBe('1. NP upraveno');

    await request(app)
      .patch(`/api/jobs/${adminJobId}/floors/${adminFloorId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ name: 'Admin test patro' });
  });

  it('cannot delete job with active seals (409)', async () => {
    const num = `8${Date.now().toString().slice(-7)}`;
    const created = await request(app)
      .post('/api/jobs')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ projectNumber: num, name: 'Stavba s ucpávkou' });
    const jobId = created.body.id;
    const floor = await request(app)
      .post(`/api/jobs/${jobId}/floors`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ name: 'Patro' });

    await request(app)
      .post('/api/seals')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({
        jobId,
        floorId: floor.body.id,
        sealNumber: '999',
        trade: 'elektrikari',
        system: 'Hilti',
        construction: 'Beton/Cihla',
        location: 'Stěna',
        fireRating: '60 min',
        entries: [
          {
            entryType: 'EL.V.',
            electroInstallationType: 'Svazek',
            dimension: 'Ø50',
            quantity: 1,
            insulation: 'žádná',
            materials: ['FiAM'],
          },
        ],
      });

    const res = await request(app)
      .delete(`/api/jobs/${jobId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({});
    expect(res.status).toBe(409);
  });

  it('management can create and delete empty job', async () => {
    const num = `9${Date.now().toString().slice(-7)}`;
    const created = await request(app)
      .post('/api/jobs')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ projectNumber: num, name: 'Dočasná stavba' });
    expect(created.status).toBe(201);
    const jobId = created.body.id;

    const floor = await request(app)
      .post(`/api/jobs/${jobId}/floors`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ name: 'Dočasné patro' });
    expect(floor.status).toBe(201);

    const delFloor = await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor.body.id}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({});
    expect(delFloor.status).toBe(200);

    const delJob = await request(app)
      .delete(`/api/jobs/${jobId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({});
    expect(delJob.status).toBe(200);
  });
});
