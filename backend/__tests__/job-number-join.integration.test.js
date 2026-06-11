import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('Worker joins a job by project number', () => {
  const app = createApp();
  const suffix = Date.now().toString().slice(-6);
  const projectPrefix = suffix.slice(-5);
  const projectNumbers = {
    active: `91${projectPrefix}`.slice(-8).padStart(8, '1'),
    completed: `92${projectPrefix}`.slice(-8).padStart(8, '2'),
    archived: `93${projectPrefix}`.slice(-8).padStart(8, '3'),
    directOnly: `94${projectPrefix}`.slice(-8).padStart(8, '4'),
  };
  const username = `join_worker_${suffix}`;
  let managementToken;
  let workerToken;
  let workerId;
  const jobIds = [];

  async function createJob(projectNumber, name) {
    const created = await request(app)
      .post('/api/jobs')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ projectNumber, name });
    expect(created.status).toBe(201);
    jobIds.push(created.body.id);
    return created.body;
  }

  beforeAll(async () => {
    const management = await request(app)
      .post('/api/auth/login')
      .send({ username: 'vedeni', pin: '1234' });
    expect(management.status).toBe(200);
    managementToken = management.body.token;

    const worker = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({
        username,
        displayName: 'Join by number worker',
        pin: '1234',
        role: 'worker',
      });
    expect(worker.status).toBe(201);
    workerId = worker.body.id;

    const login = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '1234' });
    expect(login.status).toBe(200);
    workerToken = login.body.token;

    const active = await createJob(projectNumbers.active, 'Active join job');
    await request(app)
      .post(`/api/jobs/${active.id}/floors`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ name: '1. NP' });

    const completed = await createJob(projectNumbers.completed, 'Completed join job');
    await request(app)
      .patch(`/api/jobs/${completed.id}/complete`)
      .set('Authorization', `Bearer ${managementToken}`);

    const archived = await createJob(projectNumbers.archived, 'Archived join job');
    await request(app)
      .patch(`/api/jobs/${archived.id}/archive`)
      .set('Authorization', `Bearer ${managementToken}`);

    await createJob(projectNumbers.directOnly, 'Direct access protected job');
  });

  afterAll(async () => {
    await prisma.activityLog.deleteMany({
      where: {
        OR: [
          { userId: workerId },
          { entityType: 'job', entityId: { in: jobIds } },
        ],
      },
    });
    await prisma.jobParticipant.deleteMany({
      where: { OR: [{ userId: workerId }, { jobId: { in: jobIds } }] },
    });
    await prisma.jobFloor.deleteMany({ where: { jobId: { in: jobIds } } });
    await prisma.job.deleteMany({ where: { id: { in: jobIds } } });
    await prisma.userSession.deleteMany({ where: { userId: workerId } });
    await prisma.loginLog.deleteMany({ where: { userId: workerId } });
    await prisma.user.deleteMany({ where: { id: workerId } });
    await prisma.$disconnect();
  });

  it('joins an active job once and returns it with floors', async () => {
    const first = await request(app)
      .get(`/api/jobs/by-number/${projectNumbers.active}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(first.status).toBe(200);
    expect(first.body.projectNumber).toBe(projectNumbers.active);
    expect(first.body.floors).toHaveLength(1);

    const second = await request(app)
      .get(`/api/jobs/by-number/${projectNumbers.active}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(second.status).toBe(200);

    const participants = await prisma.jobParticipant.findMany({
      where: { jobId: first.body.id, userId: workerId },
    });
    expect(participants).toHaveLength(1);
    expect(participants[0].roleOnJob).toBe('worker');

    const joins = await prisma.activityLog.count({
      where: {
        userId: workerId,
        action: 'join_by_number',
        entityType: 'job',
        entityId: first.body.id,
      },
    });
    expect(joins).toBe(1);

    const myJobs = await request(app)
      .get('/api/jobs/my')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(myJobs.status).toBe(200);
    expect(myJobs.body.some((job) => job.id === first.body.id)).toBe(true);
  });

  it.each([
    ['completed', projectNumbers.completed],
    ['archived', projectNumbers.archived],
  ])('does not join a %s job', async (_label, projectNumber) => {
    const response = await request(app)
      .get(`/api/jobs/by-number/${projectNumber}`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(response.status).toBe(404);
    expect(response.body.error).toBe('Stavba není aktivní');

    const job = await prisma.job.findUnique({ where: { projectNumber } });
    const participants = await prisma.jobParticipant.count({
      where: { jobId: job.id, userId: workerId },
    });
    expect(participants).toBe(0);
  });

  it('returns not found for an unknown project number without joining anything', async () => {
    const before = await prisma.jobParticipant.count({ where: { userId: workerId } });
    const response = await request(app)
      .get('/api/jobs/by-number/00990011')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(response.status).toBe(404);
    expect(response.body.error).toBe('Stavba s tímto číslem neexistuje');
    const after = await prisma.jobParticipant.count({ where: { userId: workerId } });
    expect(after).toBe(before);
  });

  it('keeps direct access to an unjoined job forbidden', async () => {
    const job = await prisma.job.findUnique({
      where: { projectNumber: projectNumbers.directOnly },
    });
    const response = await request(app)
      .get(`/api/jobs/${job.id}/floors`)
      .set('Authorization', `Bearer ${workerToken}`);
    expect(response.status).toBe(403);
  });
});
