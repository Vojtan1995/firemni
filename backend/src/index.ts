import * as Sentry from '@sentry/node';
import { createApp } from './app.js';
import { config, validateConfig } from './config.js';
import { logger } from './lib/logger.js';
import { startBackupScheduler } from './services/backup.service.js';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: config.nodeEnv,
  });
}

validateConfig();
const app = createApp();
startBackupScheduler();

app.listen(config.port, () => {
  logger.info(`Server běží na http://localhost:${config.port}`);
});
