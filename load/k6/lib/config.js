export function loadConfig() {
  const baseUrl = String(__ENV.BASE_URL || '').replace(/\/+$/, '');
  const expectedHost = String(__ENV.TARGET_HOST || '').toLowerCase();
  if (__ENV.ALLOW_LOAD_TEST !== 'YES') {
    throw new Error('Refusing to run: set ALLOW_LOAD_TEST=YES after verifying the staging target');
  }
  if (!baseUrl || !expectedHost) {
    throw new Error('BASE_URL and TARGET_HOST are required');
  }
  const parsed = new URL(baseUrl);
  if (parsed.hostname.toLowerCase() !== expectedHost) {
    throw new Error(`TARGET_HOST (${expectedHost}) does not match BASE_URL (${parsed.hostname})`);
  }
  if (parsed.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(parsed.hostname)) {
    throw new Error('Remote load tests require HTTPS');
  }
  if (/(^|[.-])(prod|production)([.-]|$)/i.test(parsed.hostname)) {
    throw new Error('Production-looking host rejected by the load-test safety guard');
  }
  return {
    baseUrl,
    pin: __ENV.LOAD_PIN || '654321',
    workers: Number(__ENV.LOAD_WORKERS || 50),
  };
}

export function authHeaders(token) {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

export function scenarioFor(profile) {
  const profiles = {
    baseline: [{ duration: '30s', target: 1 }, { duration: '2m', target: 1 }],
    load: [
      { duration: '2m', target: 10 },
      { duration: '3m', target: 25 },
      { duration: '3m', target: 50 },
      { duration: '2m', target: 0 },
    ],
    stress: [
      { duration: '2m', target: 25 },
      { duration: '3m', target: 50 },
      { duration: '3m', target: 100 },
      { duration: '3m', target: 150 },
      { duration: '3m', target: 200 },
      { duration: '3m', target: 0 },
    ],
    spike: [
      { duration: '30s', target: 10 },
      { duration: '15s', target: 150 },
      { duration: '3m', target: 150 },
      { duration: '1m', target: 10 },
      { duration: '30s', target: 0 },
    ],
    soak: [
      { duration: '3m', target: Number(__ENV.SOAK_VUS || 50) },
      { duration: __ENV.SOAK_DURATION || '2h', target: Number(__ENV.SOAK_VUS || 50) },
      { duration: '3m', target: 0 },
    ],
  };
  if (!profiles[profile]) throw new Error(`Unknown PROFILE=${profile}`);
  return profiles[profile];
}

export function summaryFiles(data) {
  const profile = __ENV.PROFILE || 'baseline';
  const jsonPath = __ENV.SUMMARY_JSON || `reports/k6-${profile}.json`;
  const markdownPath = __ENV.SUMMARY_MD || `reports/k6-${profile}.md`;
  const metric = (name, key) => data.metrics[name] && data.metrics[name].values[key];
  const markdown = [
    `# k6 ${profile} report`,
    '',
    `- Requests: ${metric('http_reqs', 'count') || 0}`,
    `- Failed requests: ${((metric('http_req_failed', 'rate') || 0) * 100).toFixed(2)} %`,
    `- HTTP p95: ${(metric('http_req_duration', 'p(95)') || 0).toFixed(0)} ms`,
    `- Read p95: ${(metric('read_duration', 'p(95)') || 0).toFixed(0)} ms`,
    `- Write p95: ${(metric('write_duration', 'p(95)') || 0).toFixed(0)} ms`,
    '',
  ].join('\n');
  return { [jsonPath]: JSON.stringify(data, null, 2), [markdownPath]: markdown, stdout: markdown };
}
