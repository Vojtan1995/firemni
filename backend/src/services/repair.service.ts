import { Prisma, UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { notFound } from '../lib/errors.js';
import { toNumber } from '../lib/decimal.js';
import { csvWithBom } from '../lib/csv-export.js';
import { anonymizeUserForViewer } from '../lib/user-privacy.js';
import {
  assertJobReadable,
  assertSealReadable,
  bypassesJobParticipantCheck,
  getParticipantJobIds,
} from './authorization.service.js';
import { logActivity } from './audit.service.js';
import type { RepairBody } from '../lib/repair-schemas.js';

type RepairEntryShape = {
  entryType: string;
  dimension: string;
  quantity: number;
  insulation: string;
  itemLengthMm: number | null;
  itemWidthMm: number | null;
  steelInsulated: boolean | null;
  electroInstallationType: string | null;
  materials: string[];
};

type RepairFieldsShape = {
  trade: string;
  system: string;
  construction: string;
  location: string;
  fireRating: string;
  openingLengthMm: number | null;
  openingWidthMm: number | null;
  entries: RepairEntryShape[];
};

const SCALAR_FIELDS = [
  'trade',
  'system',
  'construction',
  'location',
  'fireRating',
  'openingLengthMm',
  'openingWidthMm',
] as const;

/** Sestaví snapshot technických polí ucpávky (vč. prostupů) v okamžiku opravy. */
export function buildSealSnapshot(seal: {
  trade: string;
  system: string;
  construction: string;
  location: string;
  fireRating: string;
  openingLengthMm: number | null;
  openingWidthMm: number | null;
  entries: Array<{
    entryType: string;
    dimension: string;
    quantity: Prisma.Decimal | number | string;
    insulation: string;
    itemLengthMm: number | null;
    itemWidthMm: number | null;
    steelInsulated: boolean | null;
    electroInstallationType: string | null;
    materials: Array<{ material: string }>;
  }>;
}): RepairFieldsShape {
  return {
    trade: seal.trade,
    system: seal.system,
    construction: seal.construction,
    location: seal.location,
    fireRating: seal.fireRating,
    openingLengthMm: seal.openingLengthMm,
    openingWidthMm: seal.openingWidthMm,
    entries: seal.entries.map((e) => ({
      entryType: e.entryType,
      dimension: e.dimension,
      quantity: toNumber(e.quantity),
      insulation: e.insulation,
      itemLengthMm: e.itemLengthMm,
      itemWidthMm: e.itemWidthMm,
      steelInsulated: e.steelInsulated,
      electroInstallationType: e.electroInstallationType,
      materials: e.materials.map((m) => m.material),
    })),
  };
}

/** Sestaví hodnoty formuláře opravy ve stejném tvaru jako snapshot, pro přímé porovnání. */
export function buildRepairDataShape(body: RepairBody): RepairFieldsShape {
  return {
    trade: body.trade,
    system: body.system,
    construction: body.construction,
    location: body.location,
    fireRating: body.fireRating,
    openingLengthMm: body.openingLengthMm ?? null,
    openingWidthMm: body.openingWidthMm ?? null,
    entries: body.entries.map((e) => ({
      entryType: e.entryType,
      dimension: e.dimension,
      quantity: e.quantity,
      insulation: e.insulation,
      itemLengthMm: e.itemLengthMm ?? null,
      itemWidthMm: e.itemWidthMm ?? null,
      steelInsulated: e.steelInsulated ?? null,
      electroInstallationType: e.electroInstallationType ?? null,
      materials: e.materials,
    })),
  };
}

/** Vrátí klíče polí, které se mezi snapshotem a opravou liší (scalar pole + "entries" jako celek). */
export function diffRepair(
  original: RepairFieldsShape,
  repaired: RepairFieldsShape,
): string[] {
  const changed: string[] = [];
  for (const field of SCALAR_FIELDS) {
    if (original[field] !== repaired[field]) changed.push(field);
  }
  if (JSON.stringify(original.entries) !== JSON.stringify(repaired.entries)) {
    changed.push('entries');
  }
  return changed;
}

async function repairsJobFilter(role: UserRole, userId: string) {
  if (bypassesJobParticipantCheck(role)) return {};
  const jobIds = await getParticipantJobIds(userId);
  if (jobIds.length === 0) return { jobId: { in: [] as string[] } };
  return { jobId: { in: jobIds } };
}

const REPAIR_AUTHOR_SELECT = {
  id: true,
  displayName: true,
  username: true,
  role: true,
} as const;

export async function createSealRepair(
  sealId: string,
  userId: string,
  role: UserRole,
  body: RepairBody,
) {
  // Vynutí, že uživatel má přístup k ucpávce (worker jen účast na zakázce) —
  // žádný plošný přístup. Oprava lze vytvořit k ucpávce v jakémkoli stavu.
  const seal = await assertSealReadable(sealId, role, userId);

  const full = await prisma.seal.findFirst({
    where: { id: sealId, deletedAt: null },
    include: {
      entries: {
        where: { deletedAt: null },
        include: { materials: { orderBy: { sortOrder: 'asc' } } },
        orderBy: { sortOrder: 'asc' },
      },
    },
  });
  if (!full) throw notFound('Ucpávka nenalezena');

  const originalSnapshot = buildSealSnapshot(full);
  const repairData = buildRepairDataShape(body);
  const changedFields = diffRepair(originalSnapshot, repairData);

  // Pouze vytvoření nového záznamu opravy — žádný zápis do `seal`.
  const repair = await prisma.sealRepair.create({
    data: {
      sealId,
      jobId: seal.jobId,
      floorId: seal.floorId,
      sealNumber: seal.sealNumber,
      note: body.note,
      originalSnapshot: originalSnapshot as unknown as Prisma.InputJsonValue,
      repairData: repairData as unknown as Prisma.InputJsonValue,
      changedFields: changedFields as unknown as Prisma.InputJsonValue,
      createdById: userId,
    },
  });

  await logActivity(userId, 'create', 'seal_repair', repair.id, { sealId });

  return repair;
}

const SNAPSHOT_INCLUDE = {
  entries: {
    where: { deletedAt: null },
    include: { materials: { orderBy: { sortOrder: 'asc' as const } } },
    orderBy: { sortOrder: 'asc' as const },
  },
} as const;

/** Zachytí stav ucpávky (technická pole + prostupy) PŘED úpravou. */
export async function captureSealSnapshot(
  sealId: string,
): Promise<RepairFieldsShape | null> {
  const full = await prisma.seal.findFirst({
    where: { id: sealId, deletedAt: null },
    include: SNAPSHOT_INCLUDE,
  });
  return full ? buildSealSnapshot(full) : null;
}

/**
 * Zaznamená úpravu ucpávky jako snímek (oprava): porovná stav před a po úpravě
 * a uloží SealRepair s povinným důvodem. Když se nic nezměnilo, nevytvoří nic.
 * Slouží k dohledatelnosti úprav v jakémkoliv stavu.
 */
export async function recordSealEditRepair(
  sealId: string,
  userId: string,
  before: RepairFieldsShape,
  note: string,
): Promise<void> {
  const full = await prisma.seal.findFirst({
    where: { id: sealId, deletedAt: null },
    include: SNAPSHOT_INCLUDE,
  });
  if (!full) return;
  const after = buildSealSnapshot(full);
  const changedFields = diffRepair(before, after);
  if (changedFields.length === 0) return;

  await prisma.sealRepair.create({
    data: {
      sealId,
      jobId: full.jobId,
      floorId: full.floorId,
      sealNumber: full.sealNumber,
      note: note.trim() || 'Úprava',
      originalSnapshot: before as unknown as Prisma.InputJsonValue,
      repairData: after as unknown as Prisma.InputJsonValue,
      changedFields: changedFields as unknown as Prisma.InputJsonValue,
      createdById: userId,
    },
  });
  await logActivity(userId, 'create', 'seal_repair', sealId, {
    sealId,
    source: 'edit',
  });
}

export async function listRepairs(role: UserRole, userId: string) {
  const where = await repairsJobFilter(role, userId);
  const repairs = await prisma.sealRepair.findMany({
    where,
    include: {
      job: { select: { projectNumber: true, name: true } },
      floor: { select: { name: true } },
      createdBy: { select: REPAIR_AUTHOR_SELECT },
    },
    orderBy: { createdAt: 'desc' },
  });

  return repairs.map((r) => ({
    id: r.id,
    sealId: r.sealId,
    sealNumber: r.sealNumber,
    job: r.job,
    floor: r.floor,
    note: r.note,
    createdAt: r.createdAt,
    createdBy: anonymizeUserForViewer(r.createdBy, role),
  }));
}

export async function getRepairDetail(id: string, role: UserRole, userId: string) {
  const repair = await prisma.sealRepair.findUnique({
    where: { id },
    include: {
      job: { select: { id: true, projectNumber: true, name: true } },
      floor: { select: { id: true, name: true } },
      createdBy: { select: REPAIR_AUTHOR_SELECT },
    },
  });
  if (!repair) throw notFound('Oprava nenalezena');
  await assertJobReadable(repair.jobId, role, userId);

  return {
    id: repair.id,
    sealId: repair.sealId,
    sealNumber: repair.sealNumber,
    note: repair.note,
    originalSnapshot: repair.originalSnapshot,
    repairData: repair.repairData,
    changedFields: repair.changedFields,
    job: repair.job,
    floor: repair.floor,
    createdAt: repair.createdAt,
    createdBy: anonymizeUserForViewer(repair.createdBy, role),
  };
}

function csvCell(value: unknown): string {
  return `"${String(value).replace(/"/g, '""')}"`;
}

export async function buildRepairsCsv(
  ids: string[],
  userId: string,
  role: UserRole,
) {
  const rows: string[] = [];
  const header =
    'Číslo ucpávky;Stavba;Název stavby;Patro;Opravil;Datum opravy;Původní hodnoty;Nové hodnoty;Poznámka';

  for (const id of ids) {
    try {
      const repair = await prisma.sealRepair.findUnique({
        where: { id },
        include: {
          job: { select: { projectNumber: true, name: true } },
          floor: { select: { name: true } },
          createdBy: { select: REPAIR_AUTHOR_SELECT },
        },
      });
      if (!repair) continue;
      await assertJobReadable(repair.jobId, role, userId);

      const author = anonymizeUserForViewer(repair.createdBy, role).displayName;
      const cells = [
        repair.sealNumber,
        repair.job.projectNumber,
        repair.job.name,
        repair.floor.name,
        author,
        repair.createdAt.toISOString(),
        JSON.stringify(repair.originalSnapshot),
        JSON.stringify(repair.repairData),
        repair.note,
      ].map(csvCell);
      rows.push(cells.join(';'));
    } catch {
      // skip inaccessible
    }
  }

  return csvWithBom([header, ...rows].join('\n'));
}
