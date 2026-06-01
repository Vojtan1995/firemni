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
  corsOrigin: parseCorsOrigin(corsOriginRaw),
  allowWildcardCors: parseBoolean(process.env.ALLOW_WILDCARD_CORS, false),
  publicUploads: parseBoolean(process.env.PUBLIC_UPLOADS, true),
  sessionDays: 7,
};

export function validateConfig() {
  if (config.nodeEnv !== 'production') return;

  if (!process.env.JWT_SECRET || config.jwtSecret === 'dev-secret-change-me' || config.jwtSecret === 'change-me-in-production') {
    throw new Error('JWT_SECRET must be set to a strong non-default value in production');
  }

  const corsIsWildcard = Array.isArray(config.corsOrigin)
    ? config.corsOrigin.includes('*')
    : config.corsOrigin === '*';
  if (corsIsWildcard && !config.allowWildcardCors) {
    throw new Error('CORS_ORIGIN=* is not allowed in production unless ALLOW_WILDCARD_CORS=true is explicitly set');
  }

  if (process.env.PUBLIC_UPLOADS === undefined) {
    throw new Error('PUBLIC_UPLOADS must be explicitly set to true or false in production');
  }
}
