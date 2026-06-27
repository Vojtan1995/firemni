import http from 'k6/http';
import { check } from 'k6';
import { loadConfig } from './lib/config.js';

const BASE_URL = loadConfig().baseUrl;
const USERNAME = __ENV.ADMIN_USERNAME;
const PASSWORD = __ENV.ADMIN_PASSWORD;
const TOTP_CODE = __ENV.ADMIN_TOTP_CODE;

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ['rate==1'],
    http_req_failed: ['rate==0'],
  },
};

export default function () {
  if (!USERNAME || !PASSWORD || !TOTP_CODE) {
    throw new Error(
      'BASE_URL, ADMIN_USERNAME, ADMIN_PASSWORD and a fresh ADMIN_TOTP_CODE are required',
    );
  }
  const headers = { 'Content-Type': 'application/json' };
  const login = http.post(
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username: USERNAME, credential: PASSWORD }),
    { headers },
  );
  check(login, {
    'admin password returns MFA challenge': (r) =>
      r.status === 200 &&
      r.json('code') === 'MFA_REQUIRED' &&
      Boolean(r.json('challengeToken')) &&
      !r.json('token'),
  });

  const verify = http.post(
    `${BASE_URL}/api/auth/mfa/verify-login`,
    JSON.stringify({
      challengeToken: login.json('challengeToken'),
      code: TOTP_CODE,
    }),
    { headers },
  );
  check(verify, {
    'fresh TOTP returns full admin session': (r) =>
      r.status === 200 && Boolean(r.json('token')),
  });
}
