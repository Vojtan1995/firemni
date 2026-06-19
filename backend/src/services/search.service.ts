import { Prisma, UserRole, WorkSheetStatus, SealTrade, JobStatus } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest } from '../lib/errors.js';
import {
  applyPostSealFilters,
  buildSealFilterWhere,
  needsEntryInclude,
  parseSealFilters,
  type SealProblemFilter,
} from '../lib/seal-list-filters.js';
import { bypassesJobParticipantCheck, getParticipantJobIds } from './authorization.service.js';

const MIN_QUERY_LEN = 2;
const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 50;

const WORKSHEET_STATUS_RANK: Record<WorkSheetStatus, number> = {
  [WorkSheetStatus.draft]: 0,
  [WorkSheetStatus.submitted]: 1,
  [WorkSheetStatus.reviewed]: 2,
  [WorkSheetStatus.ready_for_invoice]: 3,
  [WorkSheetStatus.invoiced]: 4,
};

export type SearchParams = {
  role: UserRole;
  userId: string;
  q?: string;
  limit?: number;
  offset?: number;
  jobId?: string;
  floorId?: string;
  filters?: string | string[];
};

function clampLimit(limit?: number) {
  const n = limit ?? DEFAULT_LIMIT;
  return Math.min(Math.max(1, n), MAX_LIMIT);
}

async function jobScopeWhere(role: UserRole, userId: string): Promise<Prisma.SealWhereInput> {
  if (bypassesJobParticipantCheck(role)) return {};
  const jobIds = await getParticipantJobIds(userId);
  // Worker nesmí vidět ucpávky z archivovaných/dokončených zakázek – sjednoceno
  // s assertJobReadable, který workerovi neaktivní zakázky vrací jako notFound.
  return { jobId: { in: jobIds }, job: { status: JobStatus.active } };
}

function textSearchWhere(q: string, role: UserRole): Prisma.SealWhereInput {
  const term = q.trim();
  const or: Prisma.SealWhereInput[] = [
    { sealNumber: { contains: term, mode: 'insensitive' } },
    { system: { contains: term, mode: 'insensitive' } },
    { construction: { contains: term, mode: 'insensitive' } },
    { location: { contains: term, mode: 'insensitive' } },
    { fireRating: { contains: term, mode: 'insensitive' } },
    { job: { name: { contains: term, mode: 'insensitive' } } },
    { job: { projectNumber: { contains: term, mode: 'insensitive' } } },
    { floor: { name: { contains: term, mode: 'insensitive' } } },
    { createdBy: { displayName: { contains: term, mode: 'insensitive' } } },
    { createdBy: { username: { contains: term, mode: 'insensitive' } } },
    {
      entries: {
        some: {
          deletedAt: null,
          OR: [
            { entryType: { contains: term, mode: 'insensitive' } },
            { insulation: { contains: term, mode: 'insensitive' } },
            { dimension: { contains: term, mode: 'insensitive' } },
            {
              materials: {
                some: { material: { contains: term, mode: 'insensitive' } },
              },
            },
          ],
        },
      },
    },
  ];

  if (role === UserRole.worker) {
    or.push({ internalNote: { contains: term, mode: 'insensitive' } });
  } else {
    or.push({ note: { contains: term, mode: 'insensitive' } });
    or.push({ internalNote: { contains: term, mode: 'insensitive' } });
  }

  return { OR: or };
}

const sealSelect = (includeEntries: boolean) =>
  ({
    id: true,
    sealNumber: true,
    system: true,
    construction: true,
    location: true,
    fireRating: true,
    status: true,
    reviewStatus: true,
    updatedAt: true,
    jobId: true,
    floorId: true,
    job: { select: { name: true, projectNumber: true } },
    floor: { select: { name: true } },
    createdBy: { select: { displayName: true } },
    _count: { select: { photos: true } },
    ...(includeEntries
      ? {
          entries: {
            where: { deletedAt: null },
            select: {
              entryType: true,
              dimension: true,
              quantity: true,
              materials: { select: { material: true } },
            },
          },
        }
      : {}),
  }) satisfies Prisma.SealSelect;

function mapSealHit(
  s: Prisma.SealGetPayload<{ select: ReturnType<typeof sealSelect> }>,
) {
  return {
    type: 'seal' as const,
    id: s.id,
    sealNumber: s.sealNumber,
    system: s.system,
    status: s.status,
    reviewStatus: s.reviewStatus,
    jobId: s.jobId,
    jobName: s.job.name,
    projectNumber: s.job.projectNumber,
    floorId: s.floorId,
    floorName: s.floor.name,
    workerName: s.createdBy.displayName,
    photoCount: s._count.photos,
    updatedAt: s.updatedAt,
  };
}

export async function searchApp(params: SearchParams) {
  const q = (params.q ?? '').trim();
  const filters = parseSealFilters(params.filters);
  const limit = clampLimit(params.limit);
  const offset = Math.max(0, params.offset ?? 0);

  if (q.length > 0 && q.length < MIN_QUERY_LEN) {
    throw badRequest(`Dotaz musí mít alespoň ${MIN_QUERY_LEN} znaky`);
  }
  if (q.length === 0 && filters.length === 0) {
    throw badRequest('Zadejte hledaný text nebo vyberte filtr');
  }

  const scope = await jobScopeWhere(params.role, params.userId);
  const filterWhere = buildSealFilterWhere(filters, params.role);
  const includeEntries = needsEntryInclude(filters);

  const where: Prisma.SealWhereInput = {
    deletedAt: null,
    ...scope,
    ...(params.jobId ? { jobId: params.jobId } : {}),
    ...(params.floorId ? { floorId: params.floorId } : {}),
    ...(q.length > 0 ? textSearchWhere(q, params.role) : {}),
    ...filterWhere,
  };

  const rows = await prisma.seal.findMany({
    where,
    select: sealSelect(includeEntries),
    orderBy: { updatedAt: 'desc' },
    take: limit + offset + 50,
  });

  const filtered = applyPostSealFilters(rows, filters);
  const slice = filtered.slice(offset, offset + limit);

  let jobHits: Array<{
    id: string;
    name: string;
    projectNumber: string;
    isArchived: boolean;
  }> = [];
  if (q.length >= MIN_QUERY_LEN) {
    const jobWhere: Prisma.JobWhereInput = {
      deletedAt: null,
      OR: [
        { name: { contains: q, mode: 'insensitive' } },
        { projectNumber: { contains: q, mode: 'insensitive' } },
      ],
    };
    if (params.role === UserRole.worker) {
      const jobIds = await getParticipantJobIds(params.userId);
      jobWhere.id = { in: jobIds };
      jobWhere.status = JobStatus.active;
    }
    jobHits = await prisma.job.findMany({
      where: jobWhere,
      select: {
        id: true,
        name: true,
        projectNumber: true,
        isArchived: true,
      },
      take: 10,
    });
  }

  return {
    items: [
      ...jobHits.map((j) => ({
        type: 'job' as const,
        id: j.id,
        jobName: j.name,
        projectNumber: j.projectNumber,
        isArchived: j.isArchived,
      })),
      ...slice.map(mapSealHit),
    ],
    sealTotal: filtered.length,
    limit,
    offset,
  };
}

export async function listFloorSealsFiltered(options: {
  floorId: string;
  role: UserRole;
  showWorker: boolean;
  filters: SealProblemFilter[];
  trade?: SealTrade;
}) {
  const includeEntries = needsEntryInclude(options.filters);
  const filterWhere = buildSealFilterWhere(options.filters, options.role);

  const rows = await prisma.seal.findMany({
    where: {
      floorId: options.floorId,
      deletedAt: null,
      ...filterWhere,
      ...(options.trade ? { trade: options.trade } : {}),
    },
    select: {
      id: true,
      sealNumber: true,
      trade: true,
      system: true,
      status: true,
      version: true,
      updatedAt: true,
      note: true,
      internalNote: true,
      reviewStatus: true,
      markerPlacementPending: true,
      construction: true,
      location: true,
      fireRating: true,
      ...(options.showWorker
        ? { createdBy: { select: { id: true, displayName: true } } }
        : {}),
      _count: { select: { photos: true } },
      ...(includeEntries
        ? {
            entries: {
              where: { deletedAt: null },
              select: {
                entryType: true,
                dimension: true,
                quantity: true,
                materials: { select: { material: true } },
              },
            },
          }
        : {}),
    },
    orderBy: { updatedAt: 'desc' },
  });

  // Doplň „nejpokročilejší" stav soupisu, v němž ucpávka figuruje, pro badge v seznamu.
  const sealIds = rows.map((r) => r.id);
  const items = sealIds.length
    ? await prisma.workSheetItem.findMany({
        where: { sealId: { in: sealIds } },
        select: { sealId: true, worksheet: { select: { status: true } } },
      })
    : [];
  const worksheetStatusBySeal = new Map<string, WorkSheetStatus>();
  for (const i of items) {
    const prev = worksheetStatusBySeal.get(i.sealId);
    if (prev === undefined || WORKSHEET_STATUS_RANK[i.worksheet.status] > WORKSHEET_STATUS_RANK[prev]) {
      worksheetStatusBySeal.set(i.sealId, i.worksheet.status);
    }
  }
  const rowsWithBadge = rows.map((r) => ({
    ...r,
    worksheetStatus: worksheetStatusBySeal.get(r.id) ?? null,
  }));

  return applyPostSealFilters(rowsWithBadge, options.filters);
}
