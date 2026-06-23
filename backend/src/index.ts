import * as Sentry from '@sentry/node';
import { createApp } from './app.js';
import { config, validateConfig } from './config.js';
import { logger } from './lib/logger.js';
import { startBackupScheduler } from './services/backup.service.js';
import { verifyObjectStorageAccess } from './services/storage.service.js';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: config.nodeEnv,
  });
}

async function startServer() {
  validateConfig();

  if (config.storageDriver === 's3' && config.verifyStorageOnStart) {
    logger.info('Overuji object storage zapisem/ctenim docasneho objektu');
    await verifyObjectStorageAccess();
    logger.info('Object storage overeni probehlo uspesne');
  }

  const app = createApp();
  startBackupScheduler();

  app.listen(config.port, () => {
    logger.info(`Server bezi na http://localhost:${config.port}`);
  });
}

startServer().catch((error) => {
  logger.error({ err: error }, 'Server se nepodarilo spustit');
  Sentry.captureException(error);
  process.exit(1);
});
