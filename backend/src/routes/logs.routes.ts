import { Router } from 'express';
import { UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { hasPermission, requirePermission } from '../lib/permissions.js';
import { forbidden } from '../lib/errors.js';
import { prisma } from '../lib/prisma.js';
import { anonymizeUserForViewer, mapLogUsers } from '../lib/user-privacy.js';
import { parseIsoDateTimeQuery } from '../lib/zod-helpers.js';
import { describeActivity, describeChange, isDataMutation } from '../lib/log-labels.js';

const userLogSelect = { id: true, displayName: true, username: true, role: true } as const;

const router = Router();
router.use(authMiddleware);

// --- Legacy syrové endpointy (zpětná kompatibilita) – vedení/admin ---
const requireLogsView = requirePermission('logs.view');

router.get('/login', requireLogsView, async (req, res, next) => {
  try {
    const since = parseIsoDateTimeQuery(req.query.since);
    const logs = await prisma.loginLog.findMany({
      where: since ? { createdAt: { gte: since } } : {},
      include: { user: { select: userLogSelect } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(mapLogUsers(logs, req.user!.role));
  } catch (e) {
    next(e);
  }
});
router.get('/errors', requireLogsView, async (req, res, next) => {
  try {
    const since = parseIsoDateTimeQuery(req.query.since);
    const logs = await prisma.errorLog.findMany({
      where: since ? { createdAt: { gte: since } } : {},
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(logs);
  } catch (e) {
    next(e);
  }
});

router.get('/activity', requireLogsView, async (req, res, next) => {
  try {
    const since = parseIsoDateTimeQuery(req.query.since);
    const userId = req.query.userId as string | undefined;
    const entityType = req.query.entityType as string | undefined;

    const logs = await prisma.activityLog.findMany({
      where: {
        ...(since ? { createdAt: { gte: since } } : {}),
        ...(userId ? { userId } : {}),
        ...(entityType ? { entityType } : {}),
      },
      include: { user: { select: userLogSelect } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(mapLogUsers(logs, req.user!.role));
  } catch (e) {
    next(e);
  }
});

router.get('/changes', requireLogsView, async (req, res, next) => {
  try {
    const entityId = req.query.entityId as string | undefined;
    const logs = await prisma.changeLog.findMany({
      where: entityId ? { entityId } : {},
      include: { user: { select: userLogSelect } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(mapLogUsers(logs, req.user!.role));
  } catch (e) {
    next(e);
  }
});

router.get('/sync', requireLogsView, async (req, res, next) => {
  try {
    const since = parseIsoDateTimeQuery(req.query.since);
    const logs = await prisma.syncMutation.findMany({
      where: since ? { createdAt: { gte: since } } : {},
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(logs);
  } catch (e) {
    next(e);
  }
});

const PHOTO_ACTIONS = ['photo_upload', 'photo_delete'];

router.get('/photos', requireLogsView, async (req, res, next) => {
  try {
    const since = parseIsoDateTimeQuery(req.query.since);
    const logs = await prisma.activityLog.findMany({
      where: {
        action: { in: PHOTO_ACTIONS },
        ...(since ? { createdAt: { gte: since } } : {}),
      },
      include: { user: { select: userLogSelect } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(mapLogUsers(logs, req.user!.role));
  } catch (e) {
    next(e);
  }
});

const ADMIN_ACTIONS = [
  'restore',
  'soft_delete',
  'user_create',
  'user_update',
  'user_deactivate',
  'pin_reset',
  'job_archive',
  'job_delete',
  'floor_delete',
];

router.get('/admin', requireLogsView, async (req, res, next) => {
  try {
    const since = parseIsoDateTimeQuery(req.query.since);
    const logs = await prisma.activityLog.findMany({
      where: {
        action: { in: ADMIN_ACTIONS },
        ...(since ? { createdAt: { gte: since } } : {}),
      },
      include: { user: { select: userLogSelect } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json(mapLogUsers(logs, req.user!.role));
  } catch (e) {
    next(e);
  }
});

// --- Nové agregované, předformátované endpointy ---

const HISTORY_ROLES: UserRole[] = [UserRole.vedeni, UserRole.admin];

/**
 * „Historie změn" – audit datových změn (ChangeLog + mutační ActivityLog),
 * předformátovaný do českých vět s odkazem na entitu.
 */
router.get('/history', async (req, res, next) => {
  try {
    const role = req.user!.role;
    if (!HISTORY_ROLES.includes(role)) throw forbidden();
    const since = parseIsoDateTimeQuery(req.query.since);
    const entityTypeFilter = req.query.entityType as string | undefined;
    const userId = req.query.userId as string | undefined;

    const entityTypeWhere = entityTypeFilter ? { entityType: entityTypeFilter } : {};

    const [changes, activities] = await Promise.all([
      prisma.changeLog.findMany({
        where: {
          ...(since ? { createdAt: { gte: since } } : {}),
          ...(userId ? { userId } : {}),
          ...entityTypeWhere,
        },
        include: { user: { select: userLogSelect } },
        orderBy: { createdAt: 'desc' },
        take: 200,
      }),
      prisma.activityLog.findMany({
        where: {
          ...(since ? { createdAt: { gte: since } } : {}),
          ...(userId ? { userId } : {}),
          ...entityTypeWhere,
        },
        include: { user: { select: userLogSelect } },
        orderBy: { createdAt: 'desc' },
        take: 200,
      }),
    ]);

    const entries = [
      ...changes.map((c) => {
        const d = describeChange(c);
        return {
          id: c.id,
          timestamp: c.createdAt,
          title: d.title,
          entity: d.entity,
          category: d.category,
          user: anonymizeUserForViewer(c.user, role),
        };
      }),
      ...activities
        .filter((a) => isDataMutation(a.action))
        .map((a) => {
          const d = describeActivity(a);
          return {
            id: a.id,
            timestamp: a.createdAt,
            title: d.title,
            entity: d.entity,
            category: d.category,
            user: anonymizeUserForViewer(a.user, role),
          };
        }),
    ].sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

    res.json(entries);
  } catch (e) {
    next(e);
  }
});

/**
 * „Aktivita uživatelů" – přihlášení/odhlášení a změny PINu. Vedení/admin.
 */
router.get('/user-activity', requireLogsView, async (req, res, next) => {
  try {
    const role = req.user!.role;
    const since = parseIsoDateTimeQuery(req.query.since);
    const userId = req.query.userId as string | undefined;

    const [logins, activities] = await Promise.all([
      prisma.loginLog.findMany({
        where: {
          ...(since ? { createdAt: { gte: since } } : {}),
          ...(userId ? { userId } : {}),
        },
        include: { user: { select: userLogSelect } },
        orderBy: { createdAt: 'desc' },
        take: 200,
      }),
      prisma.activityLog.findMany({
        where: {
          action: { in: ['logout', 'change_pin'] },
          ...(since ? { createdAt: { gte: since } } : {}),
          ...(userId ? { userId } : {}),
        },
        include: { user: { select: userLogSelect } },
        orderBy: { createdAt: 'desc' },
        take: 200,
      }),
    ]);

    const entries = [
      ...logins.map((l) => ({
        id: l.id,
        timestamp: l.createdAt,
        title: l.success
          ? 'Přihlásil se'
          : `Neúspěšné přihlášení${l.username ? ` (${l.username})` : ''}`,
        entity: null,
        category: 'Ostatní' as const,
        user: l.user ? anonymizeUserForViewer(l.user, role) : null,
      })),
      ...activities.map((a) => {
        const d = describeActivity(a);
        return {
          id: a.id,
          timestamp: a.createdAt,
          title: d.title,
          entity: null,
          category: d.category,
          user: anonymizeUserForViewer(a.user, role),
        };
      }),
    ].sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

    res.json(entries);
  } catch (e) {
    next(e);
  }
});

/**
 * „Systém" – chyby, sync fronta a zálohy. Pouze admin.
 */
router.get('/system', async (req, res, next) => {
  try {
    if (req.user!.role !== UserRole.admin) throw forbidden();
    const since = parseIsoDateTimeQuery(req.query.since);
    const sinceWhere = since ? { createdAt: { gte: since } } : {};

    const [errors, syncs, backups] = await Promise.all([
      prisma.errorLog.findMany({ where: sinceWhere, orderBy: { createdAt: 'desc' }, take: 100 }),
      prisma.syncMutation.findMany({ where: sinceWhere, orderBy: { createdAt: 'desc' }, take: 100 }),
      prisma.backupLog.findMany({ where: sinceWhere, orderBy: { createdAt: 'desc' }, take: 100 }),
    ]);

    const entries = [
      ...errors.map((e) => {
        const isClient =
          e.metadata !== null &&
          typeof e.metadata === 'object' &&
          (e.metadata as Record<string, unknown>).source === 'client';
        return {
          id: e.id,
          timestamp: e.createdAt,
          kind: 'error' as const,
          title: `${isClient ? 'Chyba z aplikace' : 'Chyba'}: ${e.message}`,
          detail: [e.method, e.path].filter(Boolean).join(' ') || null,
        };
      }),
      ...syncs.map((s) => ({
        id: s.id,
        timestamp: s.createdAt,
        kind: 'sync' as const,
        title: `Synchronizace: ${s.entityType} ${s.operation}`,
        detail: s.processedAt ? 'Zpracováno' : 'Čeká na zpracování',
      })),
      ...backups.map((b) => ({
        id: b.id,
        timestamp: b.createdAt,
        kind: 'backup' as const,
        title: `Záloha: ${b.status}`,
        detail: b.errorMessage ?? b.fileName,
      })),
    ].sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

    res.json(entries);
  } catch (e) {
    next(e);
  }
});

/**
 * „Moje aktivita" – vlastní záznamy aktuálního uživatele. Bez logs.view (každý vidí svoje).
 */
router.get('/my-activity', async (req, res, next) => {
  try {
    const activities = await prisma.activityLog.findMany({
      where: { userId: req.user!.id },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    const entries = activities.map((a) => {
      const d = describeActivity(a);
      return {
        id: a.id,
        timestamp: a.createdAt,
        title: d.title,
        entity: d.entity,
        category: d.category,
      };
    });
    res.json(entries);
  } catch (e) {
    next(e);
  }
});

export default router;
