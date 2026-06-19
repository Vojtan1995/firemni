import { describe, it, expect, beforeAll, afterAll, afterEach } from '@jest/globals';
import request from 'supertest';
import { createApp } from '../dist/app.js';
import { prisma } from '../dist/lib/prisma.js';

const ENV_KEYS = [
  'APP_RELEASE_VERSION_NAME',
  'APP_RELEASE_BUILD',
  'APP_RELEASE_MIN_BUILD',
  'APP_RELEASE_APK_URL',
  'APP_RELEASE_NOTES',
  'APP_RELEASE_WIN_VERSION_NAME',
  'APP_RELEASE_WIN_BUILD',
  'APP_RELEASE_WIN_MIN_BUILD',
  'APP_RELEASE_WIN_URL',
  'APP_RELEASE_WIN_NOTES',
];

function saveEnv() {
  return Object.fromEntries(ENV_KEYS.map((k) => [k, process.env[k]]));
}

function restoreEnv(snapshot) {
  for (const k of ENV_KEYS) {
    if (snapshot[k] === undefined) delete process.env[k];
    else process.env[k] = snapshot[k];
  }
}

describe('GET /api/app/release', () => {
  const app = createApp();
  let envSnapshot;

  beforeAll(() => {
    envSnapshot = saveEnv();
  });

  afterEach(() => {
    restoreEnv(envSnapshot);
  });

  afterAll(async () => {
    restoreEnv(envSnapshot);
    await prisma.$disconnect();
  });

  it('returns updateAvailable false when release env is not configured', async () => {
    for (const k of ENV_KEYS) delete process.env[k];

    const res = await request(app).get('/api/app/release').query({ platform: 'android' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      platform: 'android',
      updateAvailable: false,
    });
  });

  it('returns full release info when env is configured', async () => {
    process.env.APP_RELEASE_VERSION_NAME = '1.1.0';
    process.env.APP_RELEASE_BUILD = '2';
    process.env.APP_RELEASE_MIN_BUILD = '1';
    process.env.APP_RELEASE_APK_URL = 'https://releases.example.com/ucpavky-1.1.0.apk';
    process.env.APP_RELEASE_NOTES = 'Test release notes';

    const res = await request(app).get('/api/app/release').query({ platform: 'android' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      platform: 'android',
      updateAvailable: true,
      versionName: '1.1.0',
      latestBuild: 2,
      minBuild: 1,
      apkUrl: 'https://releases.example.com/ucpavky-1.1.0.apk',
      releaseNotes: 'Test release notes',
    });
    // minBuild < latestBuild → klient může vynutit aktualizaci pro build < minBuild
    expect(res.body.minBuild).toBeLessThan(res.body.latestBuild);
  });

  it('returns updateAvailable false when APK URL is missing', async () => {
    process.env.APP_RELEASE_VERSION_NAME = '1.1.0';
    process.env.APP_RELEASE_BUILD = '2';
    delete process.env.APP_RELEASE_APK_URL;

    const res = await request(app).get('/api/app/release').query({ platform: 'android' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      platform: 'android',
      updateAvailable: false,
    });
  });

  it('returns forced-update threshold via minBuild', async () => {
    process.env.APP_RELEASE_VERSION_NAME = '2.0.0';
    process.env.APP_RELEASE_BUILD = '5';
    process.env.APP_RELEASE_MIN_BUILD = '4';
    process.env.APP_RELEASE_APK_URL = 'https://releases.example.com/ucpavky-2.0.0.apk';

    const res = await request(app).get('/api/app/release').query({ platform: 'android' });
    expect(res.status).toBe(200);
    expect(res.body.updateAvailable).toBe(true);
    expect(res.body.latestBuild).toBe(5);
    expect(res.body.minBuild).toBe(4);
  });

  it('returns updateAvailable false for windows when win release env is not configured', async () => {
    for (const k of ENV_KEYS) delete process.env[k];

    const res = await request(app).get('/api/app/release').query({ platform: 'windows' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      platform: 'windows',
      updateAvailable: false,
    });
  });

  it('returns full windows release info from APP_RELEASE_WIN_* env', async () => {
    process.env.APP_RELEASE_WIN_VERSION_NAME = '1.1.0';
    process.env.APP_RELEASE_WIN_BUILD = '4';
    process.env.APP_RELEASE_WIN_MIN_BUILD = '2';
    process.env.APP_RELEASE_WIN_URL = 'https://releases.example.com/ucpavky-setup-1.1.0.exe';
    process.env.APP_RELEASE_WIN_NOTES = 'Windows release notes';

    const res = await request(app).get('/api/app/release').query({ platform: 'windows' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      platform: 'windows',
      updateAvailable: true,
      versionName: '1.1.0',
      latestBuild: 4,
      minBuild: 2,
      apkUrl: 'https://releases.example.com/ucpavky-setup-1.1.0.exe',
      releaseNotes: 'Windows release notes',
    });
  });

  it('android and windows release env are independent', async () => {
    for (const k of ENV_KEYS) delete process.env[k];
    process.env.APP_RELEASE_BUILD = '3';
    process.env.APP_RELEASE_APK_URL = 'https://releases.example.com/app.apk';

    const android = await request(app).get('/api/app/release').query({ platform: 'android' });
    expect(android.body.updateAvailable).toBe(true);

    // Windows nemá vlastní env → žádná aktualizace, nepřebírá android hodnoty.
    const windows = await request(app).get('/api/app/release').query({ platform: 'windows' });
    expect(windows.body).toEqual({ platform: 'windows', updateAvailable: false });
  });

  it('rejects unsupported platform', async () => {
    const res = await request(app).get('/api/app/release').query({ platform: 'ios' });
    expect(res.status).toBe(400);
  });

  it('requires platform query parameter', async () => {
    const res = await request(app).get('/api/app/release');
    expect(res.status).toBe(400);
  });
});
