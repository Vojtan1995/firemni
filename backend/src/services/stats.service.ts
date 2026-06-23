import {
  SealStatus,
  UserRole,
  WorkSheetStatus,
  JobStatus,
} from "@prisma/client";
import { prisma } from "../lib/prisma.js";
import { forbidden, badRequest } from "../lib/errors.js";
import { assertJobReadable } from "./authorization.service.js";

export type StatsFilters = {
  jobId?: string;
  status?: SealStatus;
};

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

function buildSealWhere(
  role: UserRole,
  userId: string,
  scopeUserId?: string,
  filters?: StatsFilters,
) {
  const where: Record<string, unknown> = {
    deletedAt: null,
    job: { deletedAt: null, status: JobStatus.active },
  };

  if (role === UserRole.worker) {
    where.createdById = userId;
  } else if (scopeUserId) {
    where.createdById = scopeUserId;
  }

  if (filters?.jobId) where.jobId = filters.jobId;
  if (filters?.status) where.status = filters.status;

  return where;
}

async function sealCounts(
  where: Record<string, unknown>,
  statusFilter?: SealStatus,
) {
  if (statusFilter) {
    const count = await prisma.seal.count({
      where: { ...where, deletedAt: null },
    });
    return {
      total: count,
      draft: statusFilter === SealStatus.draft ? count : 0,
      checked: statusFilter === SealStatus.checked ? count : 0,
      invoiced: statusFilter === SealStatus.invoiced ? count : 0,
    };
  }
  const [total, draft, checked, invoiced] = await Promise.all([
    prisma.seal.count({ where: { ...where, deletedAt: null } }),
    prisma.seal.count({
      where: { ...where, deletedAt: null, status: SealStatus.draft },
    }),
    prisma.seal.count({
      where: { ...where, deletedAt: null, status: SealStatus.checked },
    }),
    prisma.seal.count({
      where: { ...where, deletedAt: null, status: SealStatus.invoiced },
    }),
  ]);
  return { total, draft, checked, invoiced };
}

async function photoCount(where: Record<string, unknown>) {
  return prisma.sealPhoto.count({
    where: { seal: { ...where, deletedAt: null } },
  });
}

async function missingPhotoCount(where: Record<string, unknown>) {
  return prisma.seal.count({
    where: { ...where, deletedAt: null, photos: { none: {} } },
  });
}

async function returnedSealCount(where: Record<string, unknown>) {
  return prisma.seal.count({
    where: { ...where, deletedAt: null, reviewStatus: "returned" },
  });
}

async function sealsByJob(where: Record<string, unknown>) {
  const groups = await prisma.seal.groupBy({
    by: ["jobId"],
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
    projectNumber: jobMap.get(g.jobId)?.projectNumber ?? "",
    name: jobMap.get(g.jobId)?.name ?? "",
    count: g._count.id,
  }));
}

async function sealsByJobDetailed(where: Record<string, unknown>) {
  const groups = await prisma.seal.groupBy({
    by: ["jobId", "status"],
    where: { ...where, deletedAt: null },
    _count: { id: true },
  });

  const jobIds = [...new Set(groups.map((g) => g.jobId))];
  const [jobs, missingPhotos, returned] = await Promise.all([
    prisma.job.findMany({
      where: { id: { in: jobIds } },
      select: { id: true, projectNumber: true, name: true },
    }),
    prisma.seal.groupBy({
      by: ["jobId"],
      where: { ...where, deletedAt: null, photos: { none: {} } },
      _count: { id: true },
    }),
    prisma.seal.groupBy({
      by: ["jobId"],
      where: { ...where, deletedAt: null, reviewStatus: "returned" },
      _count: { id: true },
    }),
  ]);

  const jobMap = new Map(jobs.map((j) => [j.id, j]));
  const missingMap = new Map(missingPhotos.map((m) => [m.jobId, m._count.id]));
  const returnedMap = new Map(returned.map((r) => [r.jobId, r._count.id]));

  const byJob = new Map<
    string,
    {
      jobId: string;
      projectNumber: string;
      name: string;
      total: number;
      draft: number;
      checked: number;
      invoiced: number;
      missingPhotos: number;
      returned: number;
    }
  >();

  for (const g of groups) {
    const existing = byJob.get(g.jobId) ?? {
      jobId: g.jobId,
      projectNumber: jobMap.get(g.jobId)?.projectNumber ?? "",
      name: jobMap.get(g.jobId)?.name ?? "",
      total: 0,
      draft: 0,
      checked: 0,
      invoiced: 0,
      missingPhotos: missingMap.get(g.jobId) ?? 0,
      returned: returnedMap.get(g.jobId) ?? 0,
    };
    existing.total += g._count.id;
    if (g.status === SealStatus.draft) existing.draft = g._count.id;
    if (g.status === SealStatus.checked) existing.checked = g._count.id;
    if (g.status === SealStatus.invoiced) existing.invoiced = g._count.id;
    byJob.set(g.jobId, existing);
  }

  return [...byJob.values()].sort((a, b) =>
    a.projectNumber.localeCompare(b.projectNumber),
  );
}

async function sealsByWorker(where: Record<string, unknown>) {
  const groups = await prisma.seal.groupBy({
    by: ["createdById"],
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
    displayName: userMap.get(g.createdById)?.displayName ?? "",
    count: g._count.id,
  }));
}

async function sealsByWorkerDetailed(where: Record<string, unknown>) {
  const groups = await prisma.seal.groupBy({
    by: ["createdById", "status"],
    where: { ...where, deletedAt: null },
    _count: { id: true },
  });

  const userIds = [...new Set(groups.map((g) => g.createdById))];
  const users = await prisma.user.findMany({
    where: { id: { in: userIds } },
    select: { id: true, displayName: true },
  });
  const userMap = new Map(users.map((u) => [u.id, u]));

  const byWorker = new Map<
    string,
    {
      userId: string;
      workerId: string;
      displayName: string;
      total: number;
      draft: number;
      checked: number;
      invoiced: number;
    }
  >();

  for (const g of groups) {
    const existing = byWorker.get(g.createdById) ?? {
      userId: g.createdById,
      workerId: g.createdById,
      displayName: userMap.get(g.createdById)?.displayName ?? "",
      total: 0,
      draft: 0,
      checked: 0,
      invoiced: 0,
    };
    existing.total += g._count.id;
    if (g.status === SealStatus.draft) existing.draft = g._count.id;
    if (g.status === SealStatus.checked) existing.checked = g._count.id;
    if (g.status === SealStatus.invoiced) existing.invoiced = g._count.id;
    byWorker.set(g.createdById, existing);
  }

  return [...byWorker.values()].sort((a, b) => b.total - a.total);
}

async function estimatedValue(where: Record<string, unknown>) {
  const result = await prisma.sealEntry.aggregate({
    where: {
      deletedAt: null,
      seal: { ...where, deletedAt: null },
      totalPrice: { not: null },
    },
    _sum: { totalPrice: true },
  });
  return Number(result._sum.totalPrice ?? 0);
}

async function syncPendingStats() {
  const [total, byUser] = await Promise.all([
    prisma.syncMutation.count({ where: { processedAt: null } }),
    prisma.syncMutation.groupBy({
      by: ["userId"],
      where: { processedAt: null },
      _count: { id: true },
    }),
  ]);

  const users = await prisma.user.findMany({
    where: { id: { in: byUser.map((g) => g.userId) } },
    select: { id: true, displayName: true },
  });
  const userMap = new Map(users.map((u) => [u.id, u]));

  return {
    syncPending: total,
    syncPendingByUser: byUser
      .map((g) => ({
        userId: g.userId,
        displayName: userMap.get(g.userId)?.displayName ?? "",
        count: g._count.id,
      }))
      .sort((a, b) => b.count - a.count),
  };
}

function parseStatsFilters(filters?: StatsFilters): StatsFilters | undefined {
  if (!filters?.jobId && !filters?.status) return undefined;
  return filters;
}

export async function getStatsOverview(
  role: UserRole,
  userId: string,
  scopeUserId?: string,
  filters?: StatsFilters,
) {
  if (role === UserRole.worker && scopeUserId && scopeUserId !== userId) {
    throw forbidden("Worker může vidět pouze své statistiky");
  }

  const parsedFilters = parseStatsFilters(filters);
  if (parsedFilters?.jobId) {
    await assertJobReadable(parsedFilters.jobId, role, userId);
  }
  if (
    parsedFilters?.status &&
    !Object.values(SealStatus).includes(parsedFilters.status)
  ) {
    throw badRequest("Neplatný filtr status");
  }

  const baseWhere = buildSealWhere(role, userId, scopeUserId, parsedFilters);

  const now = new Date();
  const todayWhere = { ...baseWhere, createdAt: { gte: startOfDay(now) } };
  const weekWhere = { ...baseWhere, createdAt: { gte: startOfWeek(now) } };
  const monthWhere = { ...baseWhere, createdAt: { gte: startOfMonth(now) } };

  if (role === UserRole.worker) {
    const worksheetWhere = {
      workers: { some: { userId } },
      job: { deletedAt: null, status: JobStatus.active },
      ...(parsedFilters?.jobId ? { jobId: parsedFilters.jobId } : {}),
    };

    const [
      today,
      week,
      month,
      counts,
      photos,
      missingPhotos,
      returned,
      worksheets,
      byJob,
      estimated,
    ] = await Promise.all([
      prisma.seal.count({ where: { ...todayWhere, deletedAt: null } }),
      prisma.seal.count({ where: { ...weekWhere, deletedAt: null } }),
      prisma.seal.count({ where: { ...monthWhere, deletedAt: null } }),
      sealCounts(baseWhere, parsedFilters?.status),
      photoCount(baseWhere),
      missingPhotoCount(baseWhere),
      returnedSealCount(baseWhere),
      prisma.workSheet.count({ where: worksheetWhere }),
      sealsByJob(baseWhere),
      estimatedValue(baseWhere),
    ]);

    return {
      role: "worker",
      filters: parsedFilters ?? null,
      sealsToday: today,
      sealsThisWeek: week,
      sealsThisMonth: month,
      draft: counts.draft,
      checked: counts.checked,
      invoiced: counts.invoiced,
      returnedForFix: returned,
      missingPhotos,
      photosAdded: photos,
      worksheetCount: worksheets,
      byJob,
      estimatedValueCzk: estimated,
    };
  }

  const inactiveJobsWhere = parsedFilters?.jobId
    ? { id: parsedFilters.jobId, deletedAt: null, status: JobStatus.active }
    : {
        deletedAt: null,
        status: JobStatus.active,
        seals: { none: { deletedAt: null } },
      };

  const [
    counts,
    byJob,
    byJobDetailed,
    photos,
    missingPhotos,
    returned,
    worksheets,
    readyWs,
    invoicedWs,
    unchecked,
    uninvoicedSeals,
    inactiveJobs,
    syncStats,
  ] = await Promise.all([
    sealCounts(baseWhere, parsedFilters?.status),
    sealsByJob(baseWhere),
    sealsByJobDetailed(baseWhere),
    photoCount(baseWhere),
    missingPhotoCount(baseWhere),
    returnedSealCount(baseWhere),
    parsedFilters?.jobId
      ? prisma.workSheet.count({
          where: {
            jobId: parsedFilters.jobId,
            job: { deletedAt: null, status: JobStatus.active },
          },
        })
      : prisma.workSheet.count({
          where: { job: { deletedAt: null, status: JobStatus.active } },
        }),
    prisma.workSheet.count({
      where: {
        job: { deletedAt: null, status: JobStatus.active },
        ...(parsedFilters?.jobId ? { jobId: parsedFilters.jobId } : {}),
        status: WorkSheetStatus.ready_for_invoice,
      },
    }),
    prisma.workSheet.count({
      where: {
        job: { deletedAt: null, status: JobStatus.active },
        ...(parsedFilters?.jobId ? { jobId: parsedFilters.jobId } : {}),
        status: WorkSheetStatus.invoiced,
      },
    }),
    prisma.seal.count({
      where: { ...baseWhere, deletedAt: null, status: SealStatus.draft },
    }),
    prisma.seal.count({
      where: {
        ...baseWhere,
        deletedAt: null,
        status: { in: [SealStatus.draft, SealStatus.checked] },
      },
    }),
    prisma.job.findMany({
      where: inactiveJobsWhere,
      select: { id: true, projectNumber: true, name: true },
      take: 20,
    }),
    syncPendingStats(),
  ]);

  return {
    role: role === UserRole.admin ? "admin" : "vedeni",
    filters: parsedFilters ?? null,
    totalSeals: counts.total,
    draft: counts.draft,
    checked: counts.checked,
    invoiced: counts.invoiced,
    returnedSeals: returned,
    missingPhotos,
    byJob,
    byJobDetailed,
    photosAdded: photos,
    worksheetCount: worksheets,
    readyForInvoice: readyWs,
    invoicedWorksheets: invoicedWs,
    uncheckedSeals: unchecked,
    uninvoicedWork: uninvoicedSeals,
    jobsWithoutActivity: inactiveJobs,
    syncPending: syncStats.syncPending,
    syncPendingByUser: syncStats.syncPendingByUser,
  };
}
