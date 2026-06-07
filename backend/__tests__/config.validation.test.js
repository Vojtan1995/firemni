import { describe, it, expect, afterEach } from '@jest/globals';
import { validateConfig } from '../dist/config.js';

describe('validateConfig production storage', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('requires S3 credentials when STORAGE_DRIVER=s3 in production', () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = 'prod-secret-value-12345';
    process.env.PUBLIC_UPLOADS = 'false';
    process.env.CORS_ORIGIN = 'https://app.example.com';
    process.env.STORAGE_DRIVER = 's3';
    delete process.env.S3_BUCKET;
    delete process.env.S3_ACCESS_KEY_ID;
    delete process.env.S3_SECRET_ACCESS_KEY;

    expect(() => validateConfig()).toThrow(/S3 storage requires/);
  });

  it('passes when STORAGE_DRIVER=local without S3 vars', () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_SECRET = 'prod-secret-value-12345';
    process.env.PUBLIC_UPLOADS = 'false';
    process.env.CORS_ORIGIN = 'https://app.example.com';
    process.env.STORAGE_DRIVER = 'local';

    expect(() => validateConfig()).not.toThrow();
  });
});
