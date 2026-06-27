#!/usr/bin/env node
import process from 'node:process';

const baseUrl = String(process.env.BASE_URL || '').replace(/\/+$/, '');
const targetHost = String(process.env.TARGET_HOST || '').toLowerCase();
const pin = process.env.LOAD_PIN || '654321';

function guardTarget() {
  if (process.env.ALLOW_SECURITY_TEST !== 'YES') {
    throw new Error('Set ALLOW_SECURITY_TEST=YES after confirming written authorization');
  }
  if (!baseUrl || !targetHost) throw new Error('BASE_URL and TARGET_HOST are required');
  const url = new URL(baseUrl);
  if (url.hostname.toLowerCase() !== targetHost) throw new Error('TARGET_HOST does not match BASE_URL');
  if (url.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(url.hostname)) {
    throw new Error('Remote security tests require HTTPS');
  }
  if (/(^|[.-])(prod|production)([.-]|$)/i.test(url.hostname)) {
    throw new Error('Production-looking host rejected');
  }
}

async function request(path, { token, method = 'GET', body, headers = {} } = {}) {
  return fetch(`${baseUrl}${path}`, {
    method,
    redirect: 'manual',
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

async function login(username, credential = pin) {
  const response = await request('/api/auth/login', {
    method: 'POST',
    body: { username, pin: credential },
  });
  const data = await response.json();
  if (response.status !== 200 || !data.token) throw new Error(`Login ${username} failed (${response.status})`);
  return data.token;
}

const results = [];
function record(name, passed, detail) {
  results.push({ name, passed, detail });
  console.log(`${passed ? 'PASS' : 'FAIL'} ${name}${detail ? ` — ${detail}` : ''}`);
}

guardTarget();
const unauth = await request('/api/jobs/my');
record('protected endpoint rejects anonymous request', unauth.status === 401, `HTTP ${unauth.status}`);

const badJwt = await request('/api/jobs/my', { token: 'not-a-valid-jwt' });
record('malformed JWT is rejected', badJwt.status === 401, `HTTP ${badJwt.status}`);

const workerA = await login('load_worker_1');
const workerB = await login('load_worker_2');
const jobsAResponse = await request('/api/jobs/my', { token: workerA });
const jobsBResponse = await request('/api/jobs/my', { token: workerB });
const jobsA = await jobsAResponse.json();
const jobsB = await jobsBResponse.json();
record('isolated workers have jobs', jobsA.length > 0 && jobsB.length > 0);

const foreignJob = jobsB.find((jobB) => !jobsA.some((jobA) => jobA.id === jobB.id));
if (!foreignJob) throw new Error('Seed does not provide an isolated worker-B job');
const foreignFloorsResponse = await request(`/api/jobs/${foreignJob.id}/floors`, { token: workerB });
const foreignFloors = await foreignFloorsResponse.json();
const foreignFloor = foreignFloors[0];
if (!foreignFloor) throw new Error('Worker-B job has no floor');
const foreignSealsResponse = await request(`/api/seals/floors/${foreignFloor.id}/seals`, { token: workerB });
const foreignSeals = await foreignSealsResponse.json();
const foreignSeal = foreignSeals[0];
if (!foreignSeal) throw new Error('Worker-B floor has no seal');

for (const [name, path] of [
  ['foreign job floors', `/api/jobs/${foreignJob.id}/floors`],
  ['foreign floor seals', `/api/seals/floors/${foreignFloor.id}/seals`],
  ['foreign seal detail', `/api/seals/${foreignSeal.id}`],
  ['foreign drawing metadata', `/api/jobs/${foreignJob.id}/floors/${foreignFloor.id}/drawing`],
]) {
  const response = await request(path, { token: workerA });
  record(`${name} rejects IDOR`, [403, 404].includes(response.status), `HTTP ${response.status}`);
}

const fakeLogin = await request('/api/auth/login', {
  method: 'POST',
  body: { username: `missing_${Date.now()}`, pin: 'incorrect-value' },
});
const wrongLogin = await request('/api/auth/login', {
  method: 'POST',
  body: { username: 'load_worker_1', pin: 'incorrect-value' },
});
const fakeBody = await fakeLogin.text();
const wrongBody = await wrongLogin.text();
record(
  'login response does not enumerate users',
  fakeLogin.status === wrongLogin.status && fakeBody === wrongBody,
  `HTTP ${fakeLogin.status}/${wrongLogin.status}`,
);

const oversized = await request('/api/sync/push', {
  token: workerA,
  method: 'POST',
  body: { mutations: Array.from({ length: 51 }, () => ({
    mutationId: crypto.randomUUID(),
    deviceId: 'security-smoke',
    entityType: 'seal',
    operation: 'delete',
    payload: {},
  })) },
});
record('sync batch ceiling is enforced', oversized.status === 400, `HTTP ${oversized.status}`);

const jobsAFloors = await (await request(`/api/jobs/${jobsA[0].id}/floors`, { token: workerA })).json();
const sealsA = await (await request(`/api/seals/floors/${jobsAFloors[0].id}/seals`, { token: workerA })).json();
const uploadSeal = sealsA[0];
if (uploadSeal) {
  const invalidForm = new FormData();
  invalidForm.append('photo', new Blob(['not an image'], { type: 'image/jpeg' }), 'invalid.jpg');
  const invalidUpload = await fetch(`${baseUrl}/api/seals/${uploadSeal.id}/photos`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${workerA}` },
    body: invalidForm,
  });
  record('corrupt image payload is rejected', invalidUpload.status === 400, `HTTP ${invalidUpload.status}`);

  if (process.env.TEST_UPLOAD_LIMITS === 'YES') {
    const oversizedForm = new FormData();
    oversizedForm.append(
      'photo',
      new Blob([new Uint8Array(15 * 1024 * 1024 + 1)], { type: 'image/jpeg' }),
      'oversized.jpg',
    );
    const oversizedUpload = await fetch(`${baseUrl}/api/seals/${uploadSeal.id}/photos`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${workerA}` },
      body: oversizedForm,
    });
    record('photo size ceiling is enforced', oversizedUpload.status === 413, `HTTP ${oversizedUpload.status}`);
  }
}

const health = await request('/health', { headers: { Origin: 'https://attacker.invalid' } });
record('security headers present', Boolean(health.headers.get('x-content-type-options')));
record(
  'untrusted origin is not reflected by CORS',
  health.headers.get('access-control-allow-origin') !== 'https://attacker.invalid',
  health.headers.get('access-control-allow-origin') || 'no ACAO',
);

const failed = results.filter((result) => !result.passed);
console.log(JSON.stringify({ passed: results.length - failed.length, failed: failed.length }, null, 2));
if (failed.length) process.exitCode = 1;
