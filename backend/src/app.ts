import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'path';
import { pinoHttp } from 'pino-http';
import { config } from './config.js';
import { logger } from './lib/logger.js';
import { prisma } from './lib/prisma.js';
import { errorMiddleware } from './middleware/error.middleware.js';
import authRoutes from './routes/auth.routes.js';
import jobsRoutes from './routes/jobs.routes.js';
import floorsRoutes from './routes/floors.routes.js';
import sealsRoutes from './routes/seals.routes.js';
import repairsRoutes from './routes/repairs.routes.js';
import photosRoutes from './routes/photos.routes.js';
import syncRoutes from './routes/sync.routes.js';
import reportsRoutes from './routes/reports.routes.js';
import logsRoutes from './routes/logs.routes.js';
import usersRoutes from './routes/users.routes.js';
import messagesRoutes from './routes/messages.routes.js';
import priceListRoutes from './routes/price-list.routes.js';
import worksheetsRoutes from './routes/worksheets.routes.js';
import statsRoutes from './routes/stats.routes.js';
import notificationsRoutes from './routes/notifications.routes.js';
import searchRoutes from './routes/search.routes.js';
import adminRoutes from './routes/admin.routes.js';
import appRoutes from './routes/app.routes.js';

export function createApp() {
  const app = express();

  // Railway (a každá jiná reverzní proxy) přepisuje req.ip na IP proxy.
  // Bez trust proxy by login rate limiter počítal všechny klienty pod jednou IP
  // a LoginLog.ipAddress by byl k ničemu. Hodnota 1 = důvěřuj prvnímu proxy hopu.
  app.set('trust proxy', 1);

  app.use(
    pinoHttp({
      logger,
      autoLogging: config.nodeEnv !== 'test',
    }),
  );
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors({ origin: config.corsOrigin }));
  app.use(express.json({ limit: '2mb' }));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  });

  app.get('/ready', async (_req, res, next) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      res.json({
        status: 'ready',
        database: 'ok',
        storage: {
          driver: config.storageDriver,
          publicUploads: config.publicUploads,
        },
        timestamp: new Date().toISOString(),
      });
    } catch (e) {
      next(e);
    }
  });

  if (config.publicUploads && config.storageDriver === 'local') {
    app.use('/uploads', express.static(path.resolve(config.uploadPath)));
  }

  app.use('/api/auth', authRoutes);
  app.use('/api/app', appRoutes);
  app.use('/api/jobs', jobsRoutes);
  app.use('/api/jobs/:jobId/floors', floorsRoutes);
  app.use('/api/seals', sealsRoutes);
  app.use('/api/repairs', repairsRoutes);
  app.use('/api', photosRoutes);
  app.use('/api/sync', syncRoutes);
  app.use('/api/reports', reportsRoutes);
  app.use('/api/logs', logsRoutes);
  app.use('/api/users', usersRoutes);
  app.use('/api/messages', messagesRoutes);
  app.use('/api/price-list', priceListRoutes);
  app.use('/api/worksheets', worksheetsRoutes);
  app.use('/api/stats', statsRoutes);
  app.use('/api/notifications', notificationsRoutes);
  app.use('/api/search', searchRoutes);
  app.use('/api/admin', adminRoutes);

  // Fallback 404 — musí být před errorMiddleware a za všemi routami
  app.use((_req, res) => {
    res.status(404).json({ error: 'Endpoint nenalezen', code: 'NOT_FOUND' });
  });

  app.use(errorMiddleware);

  return app;
}
