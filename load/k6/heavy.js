import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Rate, Trend } from 'k6/metrics';
import { loadConfig, summaryFiles } from './lib/config.js';

const config = loadConfig();
const BASE_URL = config.baseUrl;
const USERNAME = __ENV.LOAD_USERNAME || 'load_worker_1';
const PIN = __ENV.LOAD_PIN || '654321';
const PHOTO_PATH = __ENV.PHOTO_PATH;
const SEAL_ID = __ENV.SEAL_ID;
const JOB_ID = __ENV.JOB_ID;
const photo = PHOTO_PATH ? open(PHOTO_PATH, 'b') : null;
const errors = new Rate('heavy_errors');
const uploadDuration = new Trend('photo_upload_duration', true);
const exportDuration = new Trend('job_export_duration', true);

export const options = {
  scenarios: {
    uploads: {
      executor: 'shared-iterations',
      vus: 10,
      iterations: 50,
      maxDuration: '10m',
    },
    exports: {
      executor: 'shared-iterations',
      vus: 5,
      iterations: 20,
      maxDuration: '10m',
    },
  },
  thresholds: {
    heavy_errors: ['rate<0.01'],
    photo_upload_duration: ['p(95)<10000'],
    job_export_duration: ['p(95)<30000'],
    http_req_failed: ['rate<0.01'],
  },
};

function login() {
  const response = http.post(
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username: USERNAME, pin: PIN }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  const ok = check(response, {
    'heavy login 200': (r) => r.status === 200 && Boolean(r.json('token')),
  });
  errors.add(!ok);
  return ok ? response.json('token') : null;
}

export default function () {
  if (!PHOTO_PATH || !SEAL_ID || !JOB_ID) {
    throw new Error('PHOTO_PATH, SEAL_ID and JOB_ID are required');
  }
  const token = login();
  if (!token) return;
  const authorization = { Authorization: `Bearer ${token}` };

  if (exec.scenario.name === 'uploads') {
    const upload = http.post(
      `${BASE_URL}/api/seals/${SEAL_ID}/photos`,
      { photo: http.file(photo, `load-${__VU}-${__ITER}.jpg`, 'image/jpeg') },
      { headers: authorization, tags: { operation: '5mb_photo_upload' } },
    );
    uploadDuration.add(upload.timings.duration);
    errors.add(!check(upload, { 'photo upload 201': (r) => r.status === 201 }));
    return;
  }

  const exported = http.get(`${BASE_URL}/api/jobs/${JOB_ID}/export/pdf`, {
    headers: authorization,
    tags: { operation: 'job_pdf_export' },
    timeout: '45s',
  });
  exportDuration.add(exported.timings.duration);
  errors.add(
    !check(exported, {
      'PDF export 200': (r) =>
        r.status === 200 && String(r.headers['Content-Type'] || '').includes('application/pdf'),
    }),
  );
}

export function handleSummary(data) {
  return summaryFiles(data);
}
