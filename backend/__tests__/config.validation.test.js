import { describe, it, expect, afterEach } from '@jest/globals';
import { validateConfig } from '../dist/config.js';

describe('validateConfig production storage', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  function setSafeProductionEnv() {
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = 'prod-secret-value-12345';
    process.env.PUBLIC_UPLOADS = 'false';
    process.env.CORS_ORIGIN = 'https://app.example.com';
    process.env.BACKUP_REPORT_TOKEN = 'backup-report-token';
    process.env.BACKUP_HEALTH_TOKEN = 'backup-health-token';
    delete process.env.ALLOW_LOCAL_STORAGE_IN_PRODUCTION;
    delete process.env.S3_BUCKET;
    delete process.env.S3_ACCESS_KEY_ID;
    delete process.env.S3_SECRET_ACCESS_KEY;
    delete process.env.S3_ENDPOINT;
    delete process.env.S3_FORCE_PATH_STYLE;
  }

  it('requires S3 credentials when STORAGE_DRIVER=s3 in production', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 's3';

    expect(() => validateConfig()).toThrow(/S3 storage requires/);
  });

  it('requires S3 endpoint for R2/S3 production storage', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 's3';
    process.env.S3_BUCKET = 'bucket';
    process.env.S3_ACCESS_KEY_ID = 'key';
    process.env.S3_SECRET_ACCESS_KEY = 'secret';

    expect(() => validateConfig()).toThrow(/S3_ENDPOINT/);
  });

  it('passes when production S3/R2 vars are present', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 's3';
    process.env.S3_BUCKET = 'bucket';
    process.env.S3_ACCESS_KEY_ID = 'key';
    process.env.S3_SECRET_ACCESS_KEY = 'secret';
    process.env.S3_ENDPOINT = 'https://account.r2.cloudflarestorage.com';
    process.env.S3_FORCE_PATH_STYLE = 'true';

    expect(() => validateConfig()).not.toThrow();
  });

  it('requires backup report token in production', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 's3';
    process.env.S3_BUCKET = 'bucket';
    process.env.S3_ACCESS_KEY_ID = 'key';
    process.env.S3_SECRET_ACCESS_KEY = 'secret';
    process.env.S3_ENDPOINT = 'https://account.r2.cloudflarestorage.com';
    process.env.S3_FORCE_PATH_STYLE = 'true';
    delete process.env.BACKUP_REPORT_TOKEN;

    expect(() => validateConfig()).toThrow(/BACKUP_REPORT_TOKEN/);
  });

  it('requires backup health token in production', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 's3';
    process.env.S3_BUCKET = 'bucket';
    process.env.S3_ACCESS_KEY_ID = 'key';
    process.env.S3_SECRET_ACCESS_KEY = 'secret';
    process.env.S3_ENDPOINT = 'https://account.r2.cloudflarestorage.com';
    process.env.S3_FORCE_PATH_STYLE = 'true';
    delete process.env.BACKUP_HEALTH_TOKEN;

    expect(() => validateConfig()).toThrow(/BACKUP_HEALTH_TOKEN/);
  });

  it('requires path-style access for Cloudflare R2 endpoints', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 's3';
    process.env.S3_BUCKET = 'bucket';
    process.env.S3_ACCESS_KEY_ID = 'key';
    process.env.S3_SECRET_ACCESS_KEY = 'secret';
    process.env.S3_ENDPOINT = 'https://account.r2.cloudflarestorage.com';

    expect(() => validateConfig()).toThrow(/S3_FORCE_PATH_STYLE=true/);
  });

  it('rejects PUBLIC_UPLOADS=true in production', () => {
    setSafeProductionEnv();
    process.env.PUBLIC_UPLOADS = 'true';
    process.env.STORAGE_DRIVER = 's3';
    process.env.S3_BUCKET = 'bucket';
    process.env.S3_ACCESS_KEY_ID = 'key';
    process.env.S3_SECRET_ACCESS_KEY = 'secret';
    process.env.S3_ENDPOINT = 'https://account.r2.cloudflarestorage.com';
    process.env.S3_FORCE_PATH_STYLE = 'true';

    expect(() => validateConfig()).toThrow(/PUBLIC_UPLOADS must be false/);
  });

  it('rejects local storage in production by default', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 'local';

    expect(() => validateConfig()).toThrow(/STORAGE_DRIVER=s3 is required/);
  });

  it('allows local production storage only with explicit emergency override', () => {
    setSafeProductionEnv();
    process.env.STORAGE_DRIVER = 'local';
    process.env.ALLOW_LOCAL_STORAGE_IN_PRODUCTION = 'true';

    expect(() => validateConfig()).not.toThrow();
  });
});
