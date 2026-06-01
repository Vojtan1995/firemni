import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

describe('Users admin (management / admin)', () => {
  const app = createApp();
  let managementToken;
  let adminToken;
  let workerToken;
  let createdUserId;

  beforeAll(async () => {
    const mgmt = await request(app)
      .post('/api/auth/login')
      .send({ username: 'vedeni', pin: '1234' });
    managementToken = mgmt.body.token;

    const admin = await request(app)
      .post('/api/auth/login')
      .send({ username: 'admin', pin: '1234' });
    adminToken = admin.body.token;

    const worker = await request(app)
      .post('/api/auth/login')
      .send({ username: 'worker1', pin: '1234' });
    workerToken = worker.body.token;
  });

  async function removeTestUser(userId) {
    await prisma.userSession.deleteMany({ where: { userId } });
    await prisma.activityLog.deleteMany({ where: { userId } });
    await prisma.loginLog.deleteMany({ where: { userId } });
    await prisma.changeLog.deleteMany({ where: { userId } });
    await prisma.user.delete({ where: { id: userId } });
  }

  afterAll(async () => {
    if (createdUserId) {
      await removeTestUser(createdUserId).catch(() => {});
    }
    await prisma.$disconnect();
  });

  it('worker cannot list users', async () => {
    const res = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${workerToken}`);
    expect(res.status).toBe(403);
  });

  it('management can list users', async () => {
    const res = await request(app)
      .get('/api/users')
      .set('Authorization', `Bearer ${managementToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0]).not.toHaveProperty('pinHash');
  });

  it('management cannot create admin user', async () => {
    const res = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({
        username: 'eviladmin',
        displayName: 'Evil',
        pin: '5678',
        role: 'admin',
      });
    expect(res.status).toBe(403);
  });

  it('management can create worker and login with new pin', async () => {
    const username = `wrk_${Date.now()}`;
    const created = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${managementToken}`)
      .send({
        username,
        displayName: 'Test Worker',
        pin: '9999',
        role: 'worker',
      });
    expect(created.status).toBe(201);
    createdUserId = created.body.id;
    expect(created.body.role).toBe('worker');
    expect(created.body.mustChangePin).toBe(true);

    const login = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '9999' });
    expect(login.status).toBe(200);
    expect(login.body.user.username).toBe(username);
    expect(login.body.user.mustChangePin).toBe(true);

    const changed = await request(app)
      .post('/api/auth/change-pin')
      .set('Authorization', `Bearer ${login.body.token}`)
      .send({ currentPin: '9999', newPin: '7777' });
    expect(changed.status).toBe(200);
    expect(changed.body.mustChangePin).toBe(false);

    const me = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${login.body.token}`);
    expect(me.status).toBe(200);
    expect(me.body.mustChangePin).toBe(false);

    const oldPinLogin = await request(app)
      .post('/api/auth/login')
      .send({ username, pin: '9999' });
    expect(oldPinLogin.status).toBe(401);
  });

  it('management can PATCH pin on worker', async () => {
    const res = await request(app)
      .patch(`/api/users/${createdUserId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ pin: '8888' });
    expect(res.status).toBe(200);
    expect(res.body.mustChangePin).toBe(true);

    const login = await request(app)
      .post('/api/auth/login')
      .send({ username: (await prisma.user.findUnique({ where: { id: createdUserId } })).username, pin: '8888' });
    expect(login.status).toBe(200);
  });

  it('deactivated user cannot login', async () => {
    const deactivated = await request(app)
      .patch(`/api/users/${createdUserId}`)
      .set('Authorization', `Bearer ${managementToken}`)
      .send({ isActive: false });
    expect(deactivated.status).toBe(200);
    expect(deactivated.body.isActive).toBe(false);

    const user = await prisma.user.findUnique({ where: { id: createdUserId } });
    const login = await request(app)
      .post('/api/auth/login')
      .send({ username: user.username, pin: '8888' });
    expect(login.status).toBe(401);

    await request(app)
      .patch(`/api/users/${createdUserId}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ isActive: true });
  });

  it('admin can assign admin role', async () => {
    const username = `adm_${Date.now()}`;
    const created = await request(app)
      .post('/api/users')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        username,
        displayName: 'Test Admin',
        pin: '4321',
        role: 'admin',
      });
    expect(created.status).toBe(201);
    expect(created.body.role).toBe('admin');

    await removeTestUser(created.body.id);
  });
});
