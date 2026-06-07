const nodeEnv = process.env.NODE_ENV || 'development';
const corsOriginRaw = process.env.CORS_ORIGIN || '*';

function parseBoolean(value: string | undefined, defaultValue: boolean) {
  if (value === undefined) return defaultValue;
  return ['1', 'true', 'yes', 'on'].includes(value.toLowerCase());
}

function parseCorsOrigin(value: string) {
  if (value.includes(',')) {
    return value
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean);
  }
  return value;
}

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv,
  databaseUrl: process.env.DATABASE_URL || '',
  jwtSecret: process.env.JWT_SECRET || 'dev-secret-change-me',
  uploadPath: process.env.UPLOAD_PATH || './uploads',
  storageDriver: (process.env.STORAGE_DRIVER || 'local').toLowerCase() as 'local' | 's3',
  s3: {
    endpoint: process.env.S3_ENDPOINT,
    region: process.env.S3_REGION || 'auto',
    bucket: process.env.S3_BUCKET || '',
    accessKeyId: process.env.S3_ACCESS_KEY_ID || '',
    secretAccessKey: process.env.S3_SECRET_ACCESS_KEY || '',
    keyPrefix: process.env.S3_KEY_PREFIX || 'photos',
    forcePathStyle: parseBoolean(process.env.S3_FORCE_PATH_STYLE, false),
  },
  corsOrigin: parseCorsOrigin(corsOriginRaw),
  allowWildcardCors: parseBoolean(process.env.ALLOW_WILDCARD_CORS, false),
  publicUploads: parseBoolean(process.env.PUBLIC_UPLOADS, nodeEnv !== 'production'),
  sessionDays: 7,
};

export function validateConfig() {
  const runtimeEnv = process.env.NODE_ENV || config.nodeEnv;
  if (runtimeEnv !== 'production') return;

  if (!process.env.JWT_SECRET || config.jwtSecret === 'dev-secret-change-me' || config.jwtSecret === 'change-me-in-production') {
    throw new Error('JWT_SECRET must be set to a strong non-default value in production');
  }

  const corsOriginRaw = process.env.CORS_ORIGIN || '*';
  const corsOrigin = parseCorsOrigin(corsOriginRaw);
  const allowWildcardCors = parseBoolean(process.env.ALLOW_WILDCARD_CORS, false);
  const corsIsWildcard = Array.isArray(corsOrigin)
    ? corsOrigin.includes('*')
    : corsOrigin === '*';
  if (corsIsWildcard && !allowWildcardCors) {
    throw new Error('CORS_ORIGIN=* is not allowed in production unless ALLOW_WILDCARD_CORS=true is explicitly set');
  }

  if (process.env.PUBLIC_UPLOADS === undefined) {
    throw new Error('PUBLIC_UPLOADS must be explicitly set to true or false in production');
  }

  const storageDriver = (process.env.STORAGE_DRIVER || 'local').toLowerCase();
  if (storageDriver === 's3') {
    const missing = [
      !process.env.S3_BUCKET && 'S3_BUCKET',
      !process.env.S3_ACCESS_KEY_ID && 'S3_ACCESS_KEY_ID',
      !process.env.S3_SECRET_ACCESS_KEY && 'S3_SECRET_ACCESS_KEY',
    ].filter(Boolean);
    if (missing.length > 0) {
      throw new Error(`S3 storage requires: ${missing.join(', ')}`);
    }
  }
}
