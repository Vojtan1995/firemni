import { SealStatus, UserRole, WorkSheetStatus } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { forbidden } from '../lib/errors.js';

function startOfDay(d: Date) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

function startOfWeek(d: Date) {
  const x = startOfDay(d);
  const day = x.getDay();
  const diff = day === 0 ? 6 : day - 1;
  x.setDate(x.getDate() - diff);
  return x;
}

function startOfMonth(d: Date) {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

async function sealCounts(where: Record<string, unknown>) {
  const [total, draft, checked, invoiced] = await Promise.all([
    prisma.seal.count({ where: { ...where, deletedAt: null } }),
    prisma.seal.count({ where: { ...where, deletedAt: null, status: SealStatus.draft } }),
    prisma.seal.count({ where: { ...where, deletedAt: null, status: SealStatus.checked } }),
    prisma.seal.count({ where: { ...where, deletedAt: null, status: SealStatus.invoiced } }),
  ]);
  return { total, draft, checked, invoiced };
}

async function photoCount(where: Record<string, unknown>) {
  return prisma.sealPhoto.count({
    where: { seal: { ...where, deletedAt: null } },
  });
}

async function sealsByJob(where: Record<string, unknown>) {
  const groups = await prisma.seal.groupBy({
    by: ['jobId'],
    where: { ...where, deletedAt: null },
    _count: { id: true },
  });
  const jobs = await prisma.job.findMany({
    where: { id: { in: groups.map((g) => g.jobId) } },
    select: { id: true, projectNumber: true, name: true },
  });
  const jobMap = new Map(jobs.map((j) => [j.id, j]));
  return groups.map((g) => ({
    jobId: g.jobId,
    projectNumber: jobMap.get(g.jobId)?.projectNumber ?? '',
    name: jobMap.get(g.jobId)?.name ?? '',
    count: g._count.id,
  }));
}

async function sealsByWorker(where: Record<string, unknown>) {
  const groups = await prisma.seal.groupBy({
    by: ['createdById'],
    where: { ...where, deletedAt: null },
    _count: { id: true },
  });
  const users = await prisma.user.findMany({
    where: { id: { in: groups.map((g) => g.createdById) } },
    select: { id: true, displayName: true },
  });
  const userMap = new Map(users.map((u) => [u.id, u]));
  return groups.map((g) => ({
    userId: g.createdById,
    workerId: g.createdById,
    displayName: userMap.get(g.createdById)?.displayName ?? '',
    count: g._count.id,
  }));
}

async function estimatedValue(where: Record<string, unknown>) {
  const result = await prisma.sealEntry.aggregate({
    where: { deletedAt: null, seal: { ...where, deletedAt: null }, totalPrice: { not: null } },
    _sum: { totalPrice: true },
  });
  return Number(result._sum.totalPrice ?? 0);
}

export async function getStatsOverview(role: UserRole, userId: string, scopeUserId?: string) {
  if (role === UserRole.worker && scopeUserId && scopeUserId !== userId) {
    throw forbidden('Worker může vidět pouze své statistiky');
  }

  const now = new Date();
  const baseWhere =
    role === UserRole.worker || (scopeUserId && role !== UserRole.admin && role !== UserRole.vedeni)
      ? { createdById: scopeUserId ?? userId }
      : scopeUserId
        ? { createdById: scopeUserId }
        : {};

  const todayWhere = { ...baseWhere, createdAt: { gte: startOfDay(now) } };
  const weekWhere = { ...baseWhere, createdAt: { gte: startOfWeek(now) } };
  const monthWhere = { ...baseWhere, createdAt: { gte: startOfMonth(now) } };

  if (role === UserRole.worker) {
    const [today, week, month, counts, photos, worksheets, byJob, estimated] = await Promise.all([
      prisma.seal.count({ where: { ...todayWhere, deletedAt: null } }),
      prisma.seal.count({ where: { ...weekWhere, deletedAt: null } }),
      prisma.seal.count({ where: { ...monthWhere, deletedAt: null } }),
      sealCounts(baseWhere),
      photoCount(baseWhere),
      prisma.workSheet.count({ where: { workers: { some: { userId } } } }),
      sealsByJob(baseWhere),
      estimatedValue(baseWhere),
    ]);

    return {
      role: 'worker',
      sealsToday: today,
      sealsThisWeek: week,
      sealsThisMonth: month,
      draft: counts.draft,
      checked: counts.checked,
      returnedForFix: 0,
      photosAdded: photos,
      worksheetCount: worksheets,
      byJob,
      estimatedValueCzk: estimated,
    };
  }

  if (role === UserRole.ucetni) {
    const [total, ready, invoiced, pending, byJob, byWorker] = await Promise.all([
      prisma.workSheet.count(),
      prisma.workSheet.count({ where: { status: WorkSheetStatus.ready_for_invoice } }),
      prisma.workSheet.count({ where: { status: WorkSheetStatus.invoiced } }),
      prisma.workSheet.count({
        where: { status: { in: [WorkSheetStatus.reviewed, WorkSheetStatus.submitted] } },
      }),
      prisma.workSheet.groupBy({
        by: ['jobId'],
        _count: { id: true },
      }).then(async (groups) => {
        const jobs = await prisma.job.findMany({
          where: { id: { in: groups.map((g) => g.jobId) } },
          select: { id: true, projectNumber: true, name: true },
        });
        const jobMap = new Map(jobs.map((j) => [j.id, j]));
        return groups.map((g) => ({
          jobId: g.jobId,
          projectNumber: jobMap.get(g.jobId)?.projectNumber ?? '',
          name: jobMap.get(g.jobId)?.name ?? '',
          count: g._count.id,
        }));
      }),
      prisma.workSheetWorker.groupBy({
        by: ['userId'],
        _count: { id: true },
      }).then(async (groups) => {
        const users = await prisma.user.findMany({
          where: { id: { in: groups.map((g) => g.userId) } },
          select: { displayName: true, id: true },
        });
        const userMap = new Map(users.map((u) => [u.id, u]));
        return groups.map((g) => ({
          userId: g.userId,
          displayName: userMap.get(g.userId)?.displayName ?? '',
          count: g._count.id,
        }));
      }),
    ]);

    return {
      role: 'ucetni',
      worksheetCount: total,
      readyForInvoice: ready,
      invoiced,
      pendingInvoice: pending,
      byJob,
      byWorker,
    };
  }

  const [counts, byWorker, byJob, photos, worksheets, readyWs, invoicedWs, unchecked, uninvoicedSeals, inactiveJobs] =
    await Promise.all([
      sealCounts({}),
      sealsByWorker({}),
      sealsByJob({}),
      photoCount({}),
      prisma.workSheet.count(),
      prisma.workSheet.count({ where: { status: WorkSheetStatus.ready_for_invoice } }),
      prisma.workSheet.count({ where: { status: WorkSheetStatus.invoiced } }),
      prisma.seal.count({ where: { deletedAt: null, status: SealStatus.draft } }),
      prisma.seal.count({
        where: {
          deletedAt: null,
          status: { in: [SealStatus.draft, SealStatus.checked] },
        },
      }),
      prisma.job.findMany({
        where: { deletedAt: null, isArchived: false, seals: { none: { deletedAt: null } } },
        select: { projectNumber: true, name: true },
        take: 20,
      }),
    ]);

  return {
    role: role === UserRole.admin ? 'admin' : 'vedeni',
    totalSeals: counts.total,
    draft: counts.draft,
    checked: counts.checked,
    invoiced: counts.invoiced,
    byWorker,
    byJob,
    photosAdded: photos,
    worksheetCount: worksheets,
    readyForInvoice: readyWs,
    invoicedWorksheets: invoicedWs,
    uncheckedSeals: unchecked,
    uninvoicedWork: uninvoicedSeals,
    jobsWithoutActivity: inactiveJobs,
  };
}
