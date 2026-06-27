import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { authHeaders, loadConfig, scenarioFor, summaryFiles } from './lib/config.js';

const config = loadConfig();
const profile = __ENV.PROFILE || 'baseline';
const errors = new Rate('application_errors');
const readDuration = new Trend('read_duration', true);
const writeDuration = new Trend('write_duration', true);
const tokenFile = __ENV.TOKEN_FILE ? JSON.parse(open(__ENV.TOKEN_FILE)) : null;

export const options = {
  scenarios: {
    workload: {
      executor: 'ramping-vus',
      gracefulRampDown: '30s',
      stages: scenarioFor(profile),
    },
  },
  thresholds: {
    application_errors: [{ threshold: 'rate<0.01', abortOnFail: false }],
    read_duration: ['p(95)<1000'],
    write_duration: ['p(95)<1500'],
    http_req_failed: ['rate<0.01'],
  },
};

let token;

function measure(response, trend, label, expected = 200) {
  trend.add(response.timings.duration);
  const ok = check(response, { [`${label} ${expected}`]: (r) => r.status === expected });
  errors.add(!ok);
  return ok;
}

function ensureLogin() {
  if (token) return true;
  if (tokenFile && Array.isArray(tokenFile.tokens) && tokenFile.tokens.length) {
    token = tokenFile.tokens[(__VU - 1) % tokenFile.tokens.length];
    return true;
  }
  const worker = `load_worker_${((__VU - 1) % config.workers) + 1}`;
  const response = http.post(
    `${config.baseUrl}/api/auth/login`,
    JSON.stringify({ username: worker, pin: config.pin }),
    { headers: { 'Content-Type': 'application/json' }, tags: { endpoint: 'login' } },
  );
  if (!measure(response, writeDuration, 'login')) return false;
  token = response.json('token');
  return Boolean(token);
}

export default function () {
  if (!ensureLogin()) return;
  const headers = authHeaders(token);
  const jobs = http.get(`${config.baseUrl}/api/jobs/my`, {
    headers,
    tags: { endpoint: 'jobs_my' },
  });
  if (!measure(jobs, readDuration, 'jobs')) return;

  const jobList = jobs.json();
  const job = Array.isArray(jobList) ? jobList[__ITER % Math.max(jobList.length, 1)] : null;
  if (job && job.id) {
    const floors = http.get(`${config.baseUrl}/api/jobs/${job.id}/floors`, {
      headers,
      tags: { endpoint: 'floors' },
    });
    measure(floors, readDuration, 'floors');
    const floorList = floors.status === 200 ? floors.json() : [];
    if (Array.isArray(floorList) && floorList.length) {
      const floor = floorList[__ITER % floorList.length];
      measure(
        http.get(`${config.baseUrl}/api/seals/floors/${floor.id}/seals`, {
          headers,
          tags: { endpoint: 'seals_list' },
        }),
        readDuration,
        'seals',
      );
    }
  }

  measure(
    http.get(`${config.baseUrl}/api/stats/overview`, {
      headers,
      tags: { endpoint: 'stats' },
    }),
    readDuration,
    'stats',
  );
  measure(
    http.get(`${config.baseUrl}/api/search?q=LOAD`, {
      headers,
      tags: { endpoint: 'search' },
    }),
    readDuration,
    'search',
  );
  measure(
    http.get(`${config.baseUrl}/api/sync/pull`, {
      headers,
      tags: { endpoint: 'sync_pull' },
    }),
    readDuration,
    'sync pull',
  );
  measure(
    http.post(`${config.baseUrl}/api/sync/push`, JSON.stringify({ mutations: [] }), {
      headers,
      tags: { endpoint: 'sync_push' },
    }),
    writeDuration,
    'sync push',
  );
  sleep(Math.random() * 2 + 0.5);
}

export function handleSummary(data) {
  return summaryFiles(data);
}
