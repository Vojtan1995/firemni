const nodeEnv = process.env.NODE_ENV || 'development';
const corsOriginRaw = process.env.CORS_ORIGIN || '*';

function parseBoolean(value: string | undefined, defaultValue: boolean) {
  if (value === undefined) return defaultValue;
  return ['1', 'true', 'yes', 'on'].includes(value.toLowerCase());
}

function envBoolean(name: string, defaultValue: boolean) {
  return parseBoolean(process.env[name], defaultValue);
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
  verifyStorageOnStart: parseBoolean(process.env.VERIFY_STORAGE_ON_START, nodeEnv === 'production'),
  sessionDays: 7,
  backup: {
    enabled: parseBoolean(process.env.BACKUP_ENABLED, false),
    dir: process.env.BACKUP_DIR || './backups',
    retentionCount: parseInt(process.env.BACKUP_RETENTION_COUNT || '7', 10),
    intervalHours: parseInt(process.env.BACKUP_INTERVAL_HOURS || '24', 10),
  },
  // Retence technických logů (přihlášení s IP, chyby, zpracované sync mutace)
  // kvůli GDPR (data minimization). Běží nezávisle na zálohách.
  logRetention: {
    enabled: parseBoolean(process.env.LOG_RETENTION_ENABLED, nodeEnv === 'production'),
    days: parseInt(process.env.LOG_RETENTION_DAYS || '90', 10),
    intervalHours: parseInt(process.env.LOG_RETENTION_INTERVAL_HOURS || '24', 10),
    messageDays: parseInt(process.env.MESSAGE_RETENTION_DAYS || '365', 10),
    notificationDays: parseInt(process.env.NOTIFICATION_RETENTION_DAYS || '180', 10),
  },
  adminMfa: {
    required: parseBoolean(process.env.ADMIN_MFA_REQUIRED, false),
    dataKey: process.env.MFA_DATA_KEY || '',
    issuer: process.env.MFA_ISSUER || 'UNIFAST Ucpavky',
    challengeMinutes: 5,
    stepUpMinutes: 15,
  },
    privacyNotice: {
      version: process.env.PRIVACY_NOTICE_VERSION || '2026-06-27',
      url: process.env.PRIVACY_NOTICE_URL || '',
    },
    securityAlerts: {
      telegramBotToken: process.env.SECURITY_ALERT_TELEGRAM_BOT_TOKEN || '',
      telegramChatId: process.env.SECURITY_ALERT_TELEGRAM_CHAT_ID || '',
    },
  appRelease: {
    versionName: process.env.APP_RELEASE_VERSION_NAME || '',
    build: parseInt(process.env.APP_RELEASE_BUILD || '', 10) || 0,
    minBuild: parseInt(process.env.APP_RELEASE_MIN_BUILD || '0', 10) || 0,
    apkUrl: process.env.APP_RELEASE_APK_URL || '',
    notes: process.env.APP_RELEASE_NOTES || '',
  },
};

export function validateConfig() {
  const runtimeEnv = process.env.NODE_ENV || config.nodeEnv;
  if (runtimeEnv !== 'production') return;

  const jwtSecret = process.env.JWT_SECRET || '';
  if (!jwtSecret || jwtSecret === 'dev-secret-change-me' || jwtSecret === 'change-me-in-production') {
    throw new Error('JWT_SECRET must be set to a strong non-default value in production');
  }

  const adminMfaRequired = parseBoolean(process.env.ADMIN_MFA_REQUIRED, false);
  const mfaDataKey = process.env.MFA_DATA_KEY || '';
  if (adminMfaRequired && !/^[A-Fa-f0-9]{64}$/.test(mfaDataKey)) {
    throw new Error('MFA_DATA_KEY must be a 64-character hex key when ADMIN_MFA_REQUIRED=true');
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

  const publicUploadsRaw = process.env.PUBLIC_UPLOADS;
  if (publicUploadsRaw === undefined) {
    throw new Error('PUBLIC_UPLOADS must be explicitly set to false in production');
  }
  if (parseBoolean(publicUploadsRaw, true)) {
    throw new Error('PUBLIC_UPLOADS must be false in production');
  }

  const storageDriver = (process.env.STORAGE_DRIVER || 'local').toLowerCase();
  if (!['local', 's3'].includes(storageDriver)) {
    throw new Error('STORAGE_DRIVER must be either local or s3');
  }
  if (storageDriver !== 's3') {
    if (!envBoolean('ALLOW_LOCAL_STORAGE_IN_PRODUCTION', false)) {
      throw new Error('STORAGE_DRIVER=s3 is required in production; local storage is not persistent on Railway');
    }
    return;
  }

  if (storageDriver === 's3') {
    const missing = [
      !process.env.S3_BUCKET && 'S3_BUCKET',
      !process.env.S3_ACCESS_KEY_ID && 'S3_ACCESS_KEY_ID',
      !process.env.S3_SECRET_ACCESS_KEY && 'S3_SECRET_ACCESS_KEY',
      !process.env.S3_ENDPOINT && 'S3_ENDPOINT',
    ].filter(Boolean);
    if (missing.length > 0) {
      throw new Error(`S3 storage requires: ${missing.join(', ')}`);
    }
    const endpoint = process.env.S3_ENDPOINT || '';
    if (
      endpoint.includes('r2.cloudflarestorage.com') &&
      !envBoolean('S3_FORCE_PATH_STYLE', false)
    ) {
      throw new Error('Cloudflare R2 requires S3_FORCE_PATH_STYLE=true');
    }
  }
}
