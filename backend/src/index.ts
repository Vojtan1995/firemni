import { createApp } from './app.js';
import { config, validateConfig } from './config.js';
import { logger } from './lib/logger.js';

validateConfig();
const app = createApp();

app.listen(config.port, () => {
  logger.info(`Server běží na http://localhost:${config.port}`);
});
