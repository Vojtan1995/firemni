import { Router } from 'express';
import { config } from '../config.js';
import { authMiddleware, requireRecentAdminMfa } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { listBackupLogs, runBackup } from '../services/backup.service.js';
import { getBackupHealth, getBackupStatus, listBackupRuns } from '../services/backup-run.service.js';
import { verifyObjectStorageAccess } from '../services/storage.service.js';

const router = Router();
router.use(authMiddleware);
router.use(requirePermission('admin.backup'));

router.get('/backups', async (_req, res, next) => {
  try {
    const logs = await listBackupLogs();
    res.json(logs);
  } catch (e) {
    next(e);
  }
});

router.get('/backup-status', async (_req, res, next) => {
  try {
    const [status, runs, health] = await Promise.all([
      getBackupStatus(),
      listBackupRuns(25),
      getBackupHealth(),
    ]);
    res.json({
      ok: health.ok,
      checkedAt: health.checkedAt,
      checks: health.checks,
      status,
      runs,
    });
  } catch (e) {
    next(e);
  }
});

router.post('/backup', requireRecentAdminMfa, async (req, res, next) => {
  try {
    const log = await runBackup(req.user!.id);
    res.status(log.status === 'success' ? 201 : 500).json({
      id: log.id,
      fileName: log.fileName,
      status: log.status,
      errorMessage: log.errorMessage,
      fileSizeBytes: log.fileSizeBytes?.toString() ?? null,
      createdAt: log.createdAt,
    });
  } catch (e) {
    next(e);
  }
});

router.post('/storage/verify', requireRecentAdminMfa, async (_req, res, next) => {
  try {
    await verifyObjectStorageAccess();
    res.json({
      ok: true,
      storage: {
        driver: config.storageDriver,
        publicUploads: config.publicUploads,
      },
      checkedAt: new Date().toISOString(),
    });
  } catch (e) {
    next(e);
  }
});

export default router;
