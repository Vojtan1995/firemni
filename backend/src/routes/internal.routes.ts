import { Router } from 'express';
import { config } from '../config.js';
import { forbidden } from '../lib/errors.js';
import { getBackupHealth, recordBackupRun } from '../services/backup-run.service.js';

const router = Router();

function tokenFromHeader(value: string | undefined) {
  if (!value) return '';
  const bearer = value.match(/^Bearer\s+(.+)$/i);
  return bearer ? bearer[1] : value;
}

router.post('/backup-runs', async (req, res, next) => {
  try {
    const expected = config.backup.reportToken;
    const provided =
      tokenFromHeader(req.header('authorization')) ||
      tokenFromHeader(req.header('x-backup-report-token'));
    if (!expected || provided !== expected) {
      throw forbidden('Neplatný backup report token');
    }

    const row = await recordBackupRun(req.body);
    res.status(201).json(row);
  } catch (e) {
    next(e);
  }
});

router.get('/backup-health', async (req, res, next) => {
  try {
    const expected = config.backup.healthToken;
    const provided =
      tokenFromHeader(req.header('authorization')) ||
      tokenFromHeader(req.header('x-backup-health-token'));
    if (!expected || provided !== expected) {
      throw forbidden('Neplatny backup health token');
    }

    const health = await getBackupHealth();
    res.status(health.ok ? 200 : 503).json(health);
  } catch (e) {
    next(e);
  }
});

export default router;
