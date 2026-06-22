import { WorkSheetStatus, UserRole, SealStatus, Prisma, JobStatus } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';
import { hasPermission } from '../lib/permissions.js';
import { logActivity, logChange } from './audit.service.js';
import { notifyUsersByRoles, createNotification } from './notification.service.js';
import { csvWithBom } from '../lib/csv-export.js';
import { createCzechPdfDocument } from '../lib/pdf-pagination.js';
import { setCzechPdfBold, setCzechPdfRegular } from '../lib/pdf-fonts.js';
import { sealTradeLabel } from '../lib/seal-trade.js';
import { jobAccessDeniedMessage, jobAllowsWrites } from '../lib/job-status.js';
import { getActivePriceList, lookupPriceItem } from './pricing.service.js';

/** Vynutí, že se zakázka smí editovat (jen aktivní). Soupisy jdou zakládat,
 *  plnit a měnit jejich stav pouze na aktivní zakázce. */
function assertJobWritableStatus(status: JobStatus) {
  if (!jobAllowsWrites(status)) {
    throw forbidden(jobAccessDeniedMessage(status));
  }
}

const STATUS_TRANSITIONS: Record<WorkSheetStatus, WorkSheetStatus[]> = {
  [WorkSheetStatus.draft]: [WorkSheetStatus.submitted],
  [WorkSheetStatus.submitted]: [WorkSheetStatus.reviewed, WorkSheetStatus.draft],
  // Schválený (reviewed) → lze přímo Fakturovat (invoiced) dle 4-stavového modelu.
  // ready_for_invoice ponechán jako volitelný mezistav kvůli zpětné kompatibilitě.
  [WorkSheetStatus.reviewed]: [
    WorkSheetStatus.invoiced,
    WorkSheetStatus.ready_for_invoice,
    WorkSheetStatus.submitted,
    WorkSheetStatus.draft,
  ],
  [WorkSheetStatus.ready_for_invoice]: [WorkSheetStatus.invoiced, WorkSheetStatus.reviewed],
  [WorkSheetStatus.invoiced]: [WorkSheetStatus.reviewed, WorkSheetStatus.ready_for_invoice],
};

const STATUS_LABELS: Record<WorkSheetStatus, string> = {
  [WorkSheetStatus.draft]: 'Rozpracovaný',
  [WorkSheetStatus.submitted]: 'Odevzdaný',
  [WorkSheetStatus.reviewed]: 'Schválený',
  [WorkSheetStatus.ready_for_invoice]: 'Připravený k fakturaci',
  [WorkSheetStatus.invoiced]: 'Vyfakturovaný',
};

function assertTransition(current: WorkSheetStatus, next: WorkSheetStatus) {
  if (!STATUS_TRANSITIONS[current].includes(next)) {
    throw badRequest(`Přechod ${current} -> ${next} není povolen`);
  }
}

function assertCanTransition(
  role: UserRole,
  current: WorkSheetStatus,
  next: WorkSheetStatus,
) {
  if (role === UserRole.worker) {
    if (current !== WorkSheetStatus.draft || next !== WorkSheetStatus.submitted) {
      throw forbidden('Worker nemůže měnit stav soupisu po odevzdání');
    }
    if (!hasPermission(role, 'worksheet.submit')) {
      throw forbidden('Nemáte oprávnění odevzdat soupis');
    }
    return;
  }

  if (next === WorkSheetStatus.submitted) {
    if (!hasPermission(role, 'worksheet.review') && !hasPermission(role, 'worksheet.submit')) {
      throw forbidden('Nemáte oprávnění měnit stav soupisu');
    }
    return;
  }
  if (next === WorkSheetStatus.reviewed || next === WorkSheetStatus.draft) {
    if (!hasPermission(role, 'worksheet.review')) {
      throw forbidden('Nemáte oprávnění zkontrolovat nebo vrátit soupis');
    }
    return;
  }
  if (next === WorkSheetStatus.ready_for_invoice || next === WorkSheetStatus.invoiced) {
    if (!hasPermission(role, 'worksheet.invoice')) {
      throw forbidden('Nemáte oprávnění měnit fakturační stav soupisu');
    }
  }
}

async function assertWorksheetAccess(worksheetId: string, role: UserRole, userId: string) {
  const ws = await prisma.workSheet.findUnique({
    where: { id: worksheetId },
    include: { workers: { select: { userId: true } }, job: { select: { status: true } } },
  });
  if (!ws) throw notFound('Soupis nenalezen');
  if (role === UserRole.worker && !ws.workers.some((w) => w.userId === userId)) {
    throw forbidden('Nemáte přístup k tomuto soupisu');
  }
  return ws;
}

async function getWorksheetStatusHistory(worksheetId: string) {
  return prisma.changeLog.findMany({
    where: { entityType: 'worksheet', entityId: worksheetId, fieldName: 'status' },
    include: { user: { select: { id: true, displayName: true } } },
    orderBy: { createdAt: 'desc' },
  });
}

function sumItemTotals(items: { totalPrice: unknown }[]) {
  return items.reduce((acc, item) => acc + (item.totalPrice != null ? Number(item.totalPrice) : 0), 0);
}

export type EntryWorksheetMembership = {
  worksheetId: string;
  status: WorkSheetStatus;
  jobProjectNumber: string;
};

/**
 * Pro daný seznam ID prostupů (SealEntry) vrátí mapu sealEntryId -> info o soupisu,
 * jehož je prostup součástí. Prostup může být max v jednom soupisu (unique constraint),
 * takže mapa má vždy jeden záznam na entry.
 */
export async function getEntryWorksheetMembership(
  sealEntryIds: string[],
): Promise<Map<string, EntryWorksheetMembership>> {
  if (sealEntryIds.length === 0) return new Map();
  const items = await prisma.workSheetItem.findMany({
    where: { sealEntryId: { in: sealEntryIds } },
    select: {
      sealEntryId: true,
      worksheetId: true,
      worksheet: { select: { status: true, job: { select: { projectNumber: true } } } },
    },
  });
  return new Map(
    items.map((i) => [
      i.sealEntryId,
      {
        worksheetId: i.worksheetId,
        status: i.worksheet.status,
        jobProjectNumber: i.worksheet.job.projectNumber,
      },
    ]),
  );
}

/**
 * Vrátí info o soupisu, pokud je ucpávka „zamčená" pro přepis prostupů – tj. některý
 * z jejích aktuálních prostupů je součástí soupisu, který už opustil stav `draft`.
 * Vrací první nalezený ne-draft soupis, jinak null.
 */
export async function isSealLockedByWorksheet(
  sealId: string,
): Promise<EntryWorksheetMembership | null> {
  const entries = await prisma.sealEntry.findMany({
    where: { sealId, deletedAt: null },
    select: { id: true },
  });
  const membership = await getEntryWorksheetMembership(entries.map((e) => e.id));
  for (const m of membership.values()) {
    if (m.status !== WorkSheetStatus.draft) return m;
  }
  return null;
}

export function getAllowedStatusTargets(
  role: UserRole,
  current: WorkSheetStatus,
): WorkSheetStatus[] {
  const candidates = STATUS_TRANSITIONS[current] ?? [];
  return candidates.filter((next) => {
    try {
      assertCanTransition(role, current, next);
      return true;
    } catch {
      return false;
    }
  });
}

export async function listWorksheets(
  role: UserRole,
  userId: string,
  filters: {
    jobId?: string;
    status?: WorkSheetStatus;
    workerId?: string;
    floorId?: string;
    from?: string;
    to?: string;
    invoiced?: boolean;
  },
) {
  const where: Record<string, unknown> = {};

  if (filters.jobId) where.jobId = filters.jobId;
  if (filters.status) where.status = filters.status;
  if (filters.invoiced === true) where.status = WorkSheetStatus.invoiced;
  if (filters.invoiced === false) {
    where.status = { not: WorkSheetStatus.invoiced };
  }
  if (filters.from || filters.to) {
    where.updatedAt = {
      ...(filters.from ? { gte: new Date(filters.from) } : {}),
      ...(filters.to ? { lte: new Date(`${filters.to}T23:59:59.999Z`) } : {}),
    };
  }
  if (filters.floorId) {
    where.items = { some: { floorId: filters.floorId } };
  }

  if (role === UserRole.worker) {
    where.workers = { some: { userId } };
  } else if (filters.workerId) {
    where.workers = { some: { userId: filters.workerId } };
  }

  return prisma.workSheet.findMany({
    where,
    include: {
      job: { select: { projectNumber: true, name: true } },
      createdBy: { select: { displayName: true } },
      workers: { include: { user: { select: { id: true, displayName: true } } } },
      _count: { select: { items: true } },
      items: { select: { floor: { select: { name: true } } } },
    },
    // Nejnovější nahoře: dle data odevzdání (submittedAt), jinak dle data vytvoření.
    orderBy: [
      { submittedAt: { sort: 'desc', nulls: 'last' } },
      { createdAt: 'desc' },
    ],
  }).then((worksheets) =>
    worksheets.map(({ items, ...ws }) => ({
      ...ws,
      floorNames: [...new Set(items.map((i) => i.floor.name))].sort(),
    })),
  );
}

export async function createWorksheet(
  role: UserRole,
  userId: string,
  data: {
    jobId: string;
    workerIds?: string[];
    periodFrom?: string;
    periodTo?: string;
    note?: string;
  },
) {
  const job = await prisma.job.findFirst({ where: { id: data.jobId, deletedAt: null } });
  if (!job) throw notFound('Zakázka nenalezena');
  assertJobWritableStatus(job.status);

  let workerIds = data.workerIds ?? [];
  if (role === UserRole.worker) {
    if (workerIds.some((id) => id !== userId)) {
      throw forbidden('Worker může vytvořit soupis pouze za sebe');
    }
    workerIds = [userId];
  } else if (workerIds.length === 0) {
    throw badRequest('Vyberte alespoň jednoho pracovníka');
  }

  const worksheet = await prisma.workSheet.create({
    data: {
      jobId: data.jobId,
      createdById: userId,
      periodFrom: data.periodFrom ? new Date(data.periodFrom) : undefined,
      periodTo: data.periodTo ? new Date(data.periodTo) : undefined,
      note: data.note,
      workers: {
        create: workerIds.map((wid) => ({ userId: wid })),
      },
    },
    include: {
      job: { select: { projectNumber: true, name: true } },
      workers: { include: { user: { select: { id: true, displayName: true } } } },
    },
  });

  await logActivity(userId, 'worksheet_create', 'worksheet', worksheet.id);
  return worksheet;
}

export async function getWorksheet(id: string, role: UserRole, userId: string) {
  await assertWorksheetAccess(id, role, userId);

  const worksheet = await prisma.workSheet.findUnique({
    where: { id },
    include: {
      job: { select: { projectNumber: true, name: true, address: true } },
      createdBy: { select: { displayName: true } },
      workers: { include: { user: { select: { id: true, displayName: true } } } },
      items: {
        orderBy: { sortOrder: 'asc' },
        include: { floor: { select: { name: true } } },
      },
    },
  });
  if (!worksheet) throw notFound('Soupis nenalezen');

  const statusHistory = await getWorksheetStatusHistory(id);
  const totalValue = sumItemTotals(worksheet.items);
  const allowedStatusTargets = getAllowedStatusTargets(role, worksheet.status);

  return {
    ...worksheet,
    totalValue,
    itemCount: worksheet.items.length,
    statusHistory,
    allowedStatusTargets,
  };
}

/**
 * Smaže rozpracovaný (draft) soupis. Volíme hard delete – soupisy jsou pouze
 * serverové (žádná offline/Drift tabulka), draft nebyl nikdy odevzdán a položky
 * i účastníci mají onDelete: Cascade, takže smazání neovlivní ucpávky, historii
 * ani audit (WorkSheetItem referencuje Seal, ne naopak). Worker je omezen na
 * vlastní/účastnický soupis přes assertWorksheetAccess.
 */
export async function deleteWorksheet(id: string, role: UserRole, userId: string) {
  const ws = await assertWorksheetAccess(id, role, userId);
  if (ws.status !== WorkSheetStatus.draft) {
    throw badRequest('Smazat lze jen rozpracovaný soupis');
  }
  await prisma.workSheet.delete({ where: { id } });
  await logActivity(userId, 'worksheet_delete', 'worksheet', id);
  return { id };
}

async function assertWorksheetEditable(worksheetId: string, role: UserRole, userId: string) {
  const ws = await assertWorksheetAccess(worksheetId, role, userId);
  if (ws.status !== WorkSheetStatus.draft) {
    throw badRequest('Upravit lze pouze rozpracovaný soupis');
  }
  return ws;
}

export async function addWorksheetItems(
  worksheetId: string,
  role: UserRole,
  userId: string,
  sealEntryIds: string[],
) {
  const ws = await assertWorksheetEditable(worksheetId, role, userId);
  assertJobWritableStatus(ws.job.status);

  const entries = await prisma.sealEntry.findMany({
    where: { id: { in: sealEntryIds }, deletedAt: null },
    include: {
      materials: { orderBy: { sortOrder: 'asc' } },
      seal: {
        include: {
          floor: { select: { id: true, name: true } },
        },
      },
    },
  });

  if (entries.length !== sealEntryIds.length) {
    throw badRequest('Některé položky nebyly nalezeny');
  }

  const existingItems = await prisma.workSheetItem.findMany({
    where: { sealEntryId: { in: sealEntryIds } },
    select: { sealEntryId: true, worksheetId: true },
  });
  if (existingItems.some((item) => item.worksheetId !== worksheetId)) {
    throw badRequest('Některé položky jsou již v jiném soupisu');
  }
  if (existingItems.some((item) => item.worksheetId === worksheetId)) {
    throw badRequest('Některé položky jsou již v tomto soupisu');
  }

  for (const entry of entries) {
    if (entry.seal.jobId !== ws.jobId) {
      throw badRequest('Všechny položky musí patřit ke stejné zakázce');
    }
    if (entry.seal.deletedAt) {
      throw badRequest('Ucpávka byla smazána');
    }
    if (entry.seal.status === SealStatus.invoiced) {
      throw badRequest('Vyfakturovanou ucpávku nelze přidat do soupisu');
    }
    if (role === UserRole.worker && entry.seal.createdById !== userId) {
      throw forbidden('Worker může přidat pouze vlastní položky');
    }
  }

  const existingCount = await prisma.workSheetItem.count({ where: { worksheetId } });

  // Cena se počítá až při vytvoření soupisu – z AKTUÁLNÍHO ceníku – a uloží se
  // jako snapshot do položky soupisu (Task 7). Pozdější změna ceníku už soupis nemění.
  const activePriceList = await getActivePriceList();
  const itemData = await Promise.all(
    entries.map(async (entry, i) => {
      const quantity = entry.quantity;
      const unit = entry.unit ?? 'kus';
      const preferredUnit = unit !== 'kus' ? (unit as 'm2' | 'mb') : undefined;
      const match = activePriceList
        ? await lookupPriceItem(
            {
              entryType: entry.entryType,
              dimension: entry.dimension,
              insulation: entry.insulation,
              quantity: Number(quantity),
              preferredUnit,
            },
            activePriceList,
          )
        : null;
      const unitPrice = match ? Number(match.item.priceWithMaterial) : null;
      const totalPrice = unitPrice != null ? unitPrice * Number(quantity) : null;
      const catalogId = entry.materials.map((m) => m.material).join(', ');
      return {
        worksheetId,
        sealId: entry.sealId,
        sealEntryId: entry.id,
        floorId: entry.seal.floorId,
        workerId: entry.seal.createdById,
        sealNumber: entry.seal.sealNumber,
        trade: entry.seal.trade,
        entryType: entry.entryType,
        dimension: entry.dimension,
        quantity,
        unit,
        system: entry.seal.system,
        insulation: entry.insulation,
        location: entry.seal.location,
        catalogId: catalogId.length > 0 ? catalogId : null,
        unitPrice,
        totalPrice,
        priceListVersion: match ? match.priceList.version : null,
        sortOrder: existingCount + i,
      };
    }),
  );

  // Aplikační kontrola výše (existingItems) běží read-then-write a neochrání
  // proti souběhu requestů. Tvrdou pojistku dává unique index na sealEntryId –
  // při závodu Prisma vyhodí P2002, který přemapujeme na čistou hlášku.
  const created = await prisma
    .$transaction(itemData.map((data) => prisma.workSheetItem.create({ data })))
    .catch((e) => {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        throw badRequest('Některé položky jsou již v jiném soupisu');
      }
      throw e;
    });

  await logActivity(userId, 'worksheet_add_items', 'worksheet', worksheetId, {
    count: created.length,
  });
  return created;
}

export async function changeWorksheetStatus(
  worksheetId: string,
  nextStatus: WorkSheetStatus,
  role: UserRole,
  userId: string,
  comment?: string,
) {
  const ws = await assertWorksheetAccess(worksheetId, role, userId);
  assertJobWritableStatus(ws.job.status);

  assertTransition(ws.status, nextStatus);
  assertCanTransition(role, ws.status, nextStatus);

  if (nextStatus === WorkSheetStatus.draft && ws.status !== WorkSheetStatus.draft) {
    if (role !== UserRole.worker && !comment?.trim()) {
      throw badRequest('Při vrácení soupisu je povinný důvod');
    }
  }

  const now = new Date();
  const timestamps: Record<string, Date | null> = {};
  if (nextStatus === WorkSheetStatus.submitted) timestamps.submittedAt = now;
  if (nextStatus === WorkSheetStatus.reviewed) timestamps.reviewedAt = now;
  if (nextStatus === WorkSheetStatus.ready_for_invoice) timestamps.readyForInvoiceAt = now;
  if (nextStatus === WorkSheetStatus.invoiced) timestamps.invoicedAt = now;

  if (nextStatus === WorkSheetStatus.draft) {
    timestamps.submittedAt = null;
    timestamps.reviewedAt = null;
    timestamps.readyForInvoiceAt = null;
    timestamps.invoicedAt = null;
  } else if (nextStatus === WorkSheetStatus.submitted) {
    timestamps.reviewedAt = null;
    timestamps.readyForInvoiceAt = null;
    timestamps.invoicedAt = null;
  } else if (nextStatus === WorkSheetStatus.reviewed) {
    timestamps.readyForInvoiceAt = null;
    timestamps.invoicedAt = null;
  } else if (nextStatus === WorkSheetStatus.ready_for_invoice) {
    timestamps.invoicedAt = null;
  }

  const updated = await prisma.workSheet.update({
    where: { id: worksheetId },
    data: { status: nextStatus, ...timestamps },
    include: {
      job: { select: { projectNumber: true, name: true } },
      workers: { include: { user: { select: { displayName: true } } } },
      items: true,
    },
  });

  await logActivity(userId, 'worksheet_status', 'worksheet', worksheetId, {
    from: ws.status,
    to: nextStatus,
    comment: comment ?? null,
  });

  await logChange(userId, 'worksheet', worksheetId, 'status', ws.status, nextStatus, {
    comment: comment ?? null,
  });

  if (nextStatus === WorkSheetStatus.submitted) {
    await notifyUsersByRoles([UserRole.vedeni, UserRole.admin], {
      type: 'worksheet_submitted',
      title: 'Nový soupis k odsouhlasení',
      body: `Soupis byl odevzdán (${updated.job.projectNumber})`,
      entityType: 'worksheet',
      entityId: worksheetId,
    });
  }
  if (nextStatus === WorkSheetStatus.draft && ws.status !== WorkSheetStatus.draft) {
    for (const w of updated.workers) {
      await createNotification({
        userId: w.userId,
        type: 'worksheet_returned',
        title: 'Soupis vrácen k opravě',
        body: comment?.trim() || 'Soupis byl vrácen k opravě',
        entityType: 'worksheet',
        entityId: worksheetId,
      });
    }
  }
  if (nextStatus === WorkSheetStatus.reviewed) {
    for (const w of updated.workers) {
      await createNotification({
        userId: w.userId,
        type: 'worksheet_approved',
        title: 'Soupis schválen',
        body: `Soupis ${updated.job.projectNumber} byl schválen`,
        entityType: 'worksheet',
        entityId: worksheetId,
      });
    }
  }

  return updated;
}

export async function populateWorksheetFromFilters(
  worksheetId: string,
  role: UserRole,
  userId: string,
  filters: {
    floorIds?: string[];
    status?: string;
    system?: string;
    entryType?: string;
    from?: string;
    to?: string;
  },
) {
  const ws = await assertWorksheetEditable(worksheetId, role, userId);
  const workerIds = (
    await prisma.workSheetWorker.findMany({ where: { worksheetId }, select: { userId: true } })
  ).map((w) => w.userId);

  const sealWhere: Record<string, unknown> = {
    jobId: ws.jobId,
    deletedAt: null,
    createdById: role === UserRole.worker ? userId : { in: workerIds },
  };
  if (filters.floorIds?.length) sealWhere.floorId = { in: filters.floorIds };
  if (filters.status) {
    sealWhere.status = filters.status;
  } else {
    sealWhere.status = { in: [SealStatus.draft, SealStatus.checked] };
  }
  if (filters.from || filters.to) {
    sealWhere.createdAt = {};
    if (filters.from) (sealWhere.createdAt as Record<string, Date>).gte = new Date(filters.from);
    if (filters.to) (sealWhere.createdAt as Record<string, Date>).lte = new Date(filters.to);
  }

  // Vynech prostupy, které už jsou v jakémkoliv soupisu – jinak by jediná zabraná
  // položka shodila celý dávkový import přes addWorksheetItems.
  const entryWhere: Record<string, unknown> = {
    deletedAt: null,
    seal: sealWhere,
    worksheetItems: { none: {} },
  };
  if (filters.entryType) entryWhere.entryType = filters.entryType;
  if (filters.system) {
    sealWhere.system = filters.system;
  }

  const entries = await prisma.sealEntry.findMany({
    where: entryWhere,
    select: { id: true },
  });

  const created = await addWorksheetItems(
    worksheetId,
    role,
    userId,
    entries.map((e) => e.id),
  );

  return { items: created, requestedCount: entries.length, addedCount: created.length };
}

async function loadWorksheetExportData(id: string, role: UserRole, userId: string) {
  await assertWorksheetAccess(id, role, userId);

  const worksheet = await prisma.workSheet.findUnique({
    where: { id },
    include: {
      job: true,
      createdBy: { select: { displayName: true } },
      workers: { include: { user: { select: { displayName: true } } } },
      items: { orderBy: { sortOrder: 'asc' } },
    },
  });
  if (!worksheet) throw notFound('Soupis nenalezen');

  const floorIds = [...new Set(worksheet.items.map((i) => i.floorId))];
  const floors = floorIds.length
    ? await prisma.jobFloor.findMany({
        where: { id: { in: floorIds } },
        select: { id: true, name: true },
      })
    : [];
  const floorMap = new Map(floors.map((f: { id: string; name: string }) => [f.id, f.name]));

  const workerIds = [...new Set(worksheet.items.map((i) => i.workerId))];
  const workers = workerIds.length
    ? await prisma.user.findMany({
        where: { id: { in: workerIds } },
        select: { id: true, displayName: true },
      })
    : [];
  const workerMap = new Map(workers.map((w) => [w.id, w.displayName]));

  type ExportItemRow = {
    patro: string;
    prostup: string;
    remeslo: string;
    system: string;
    katalogId: string;
    typ: string;
    rozmer: string;
    pocet: number;
    izolace: string;
    umisteni: string;
    provedl: string;
    jednotkovaCena: number | null;
    cenaCelkem: number | null;
  };

  const rows: ExportItemRow[] = worksheet.items.map((item) => ({
    patro: String(floorMap.get(item.floorId) ?? item.floorId),
    prostup: item.sealNumber,
    remeslo: sealTradeLabel(item.trade),
    system: item.system ?? '',
    katalogId: item.catalogId ?? '',
    typ: item.entryType,
    rozmer: item.dimension,
    pocet: Number(item.quantity),
    izolace: item.insulation ?? '',
    umisteni: item.location ?? '',
    provedl: workerMap.get(item.workerId) ?? '',
    jednotkovaCena: item.unitPrice != null ? Number(item.unitPrice) : null,
    cenaCelkem: item.totalPrice != null ? Number(item.totalPrice) : null,
  }));

  // Řazení uvnitř exportu: Podlaží → Prostup → Typ položky.
  rows.sort((a, b) => {
    if (a.patro !== b.patro) return a.patro.localeCompare(b.patro, 'cs');
    const pa = parseInt(a.prostup, 10);
    const pb = parseInt(b.prostup, 10);
    if (Number.isFinite(pa) && Number.isFinite(pb) && pa !== pb) return pa - pb;
    if (a.prostup !== b.prostup) return a.prostup.localeCompare(b.prostup, 'cs');
    return a.typ.localeCompare(b.typ, 'cs');
  });

  // Seskupení podle podlaží (v pořadí dle seřazených řádků) + součet za podlaží.
  const floorGroups: { floorName: string; rows: ExportItemRow[]; floorTotal: number }[] = [];
  for (const row of rows) {
    let group = floorGroups.find((g) => g.floorName === row.patro);
    if (!group) {
      group = { floorName: row.patro, rows: [], floorTotal: 0 };
      floorGroups.push(group);
    }
    group.rows.push(row);
    group.floorTotal += row.cenaCelkem ?? 0;
  }

  return { worksheet, rows, floorGroups, total: sumItemTotals(worksheet.items) };
}

// Pořadí sloupců dle PDF vzoru (Task 9). Řemeslo je nový sloupec.
const EXPORT_COLUMNS = [
  { key: 'patro', label: 'Podlaží', width: 46, align: 'center' as const },
  { key: 'prostup', label: 'Prostup', width: 46, align: 'center' as const },
  { key: 'remeslo', label: 'Řemeslo', width: 68, align: 'left' as const },
  { key: 'system', label: 'Systém', width: 60, align: 'left' as const },
  { key: 'katalogId', label: 'Katalog ID', width: 92, align: 'left' as const, wrap: true },
  { key: 'typ', label: 'Typ', width: 52, align: 'left' as const, wrap: true },
  { key: 'rozmer', label: 'Rozměr', width: 66, align: 'left' as const },
  { key: 'pocet', label: 'Počet', width: 40, align: 'center' as const },
  { key: 'izolace', label: 'Izolace', width: 58, align: 'left' as const },
  { key: 'umisteni', label: 'Umístění v PÚ', width: 66, align: 'left' as const },
  { key: 'provedl', label: 'Provedl', width: 70, align: 'left' as const },
  { key: 'jednotkovaCena', label: 'Jednotková cena', width: 60, align: 'right' as const, money: true },
  { key: 'cenaCelkem', label: 'Cena celkem', width: 60, align: 'right' as const, money: true },
];

function csvCell(value: unknown): string {
  return `"${String(value ?? '').replace(/"/g, '""')}"`;
}

function money(value: number | null | undefined): string {
  return value != null ? `${Number(value).toFixed(2)} Kč` : '';
}

export async function exportWorksheetCsv(id: string, role: UserRole, userId: string) {
  const { worksheet, floorGroups, total } = await loadWorksheetExportData(id, role, userId);
  const colCount = EXPORT_COLUMNS.length;
  const header = EXPORT_COLUMNS.map((c) => csvCell(c.label)).join(';');
  const lines: string[] = [header];

  for (const group of floorGroups) {
    for (const row of group.rows) {
      lines.push(
        EXPORT_COLUMNS.map((c) => {
          const v = (row as Record<string, unknown>)[c.key];
          return csvCell(c.money ? money(v as number | null) : v);
        }).join(';'),
      );
    }
    // Řádek "Cena za podlaží" – součet v posledním sloupci.
    const floorTotalCells = new Array(colCount).fill('""');
    floorTotalCells[0] = csvCell(`Cena za podlaží – ${group.floorName}`);
    floorTotalCells[colCount - 1] = csvCell(money(group.floorTotal));
    lines.push(floorTotalCells.join(';'));
  }

  const totalCells = new Array(colCount).fill('""');
  totalCells[0] = csvCell('Cena celkem bez DPH');
  totalCells[colCount - 1] = csvCell(money(total));
  lines.push(totalCells.join(';'));
  lines.push(`${csvCell('Datum')};${csvCell(new Date().toISOString().split('T')[0])}`);

  const csv = csvWithBom(lines.join('\n'));
  const filename = `soupis-${worksheet.job.projectNumber}-${worksheet.id.slice(0, 8)}.csv`;
  return { csv, filename };
}

export async function exportWorksheetPdf(
  id: string,
  role: UserRole,
  userId: string,
  res: import('express').Response,
) {
  const { worksheet, floorGroups, total } = await loadWorksheetExportData(id, role, userId);

  const filename = `soupis-${worksheet.job.projectNumber}-${worksheet.id.slice(0, 8)}.pdf`;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

  // PDF vždy na šířku (landscape).
  const margin = 28;
  const doc = createCzechPdfDocument({ margin, size: 'A4', layout: 'landscape' });
  doc.pipe(res);

  const pageRight = doc.page.width - margin;
  const tableWidth = EXPORT_COLUMNS.reduce((s, c) => s + c.width, 0);
  const scale = (pageRight - margin) / tableWidth;
  const colWidths = EXPORT_COLUMNS.map((c) => c.width * scale);
  const bottomY = doc.page.height - margin - 60;

  const periodFrom = worksheet.periodFrom?.toISOString().split('T')[0] ?? '—';
  const periodTo = worksheet.periodTo?.toISOString().split('T')[0] ?? '—';
  const workerNames = worksheet.workers.map((w) => w.user.displayName).join(', ');
  const itemCount = floorGroups.reduce((s, g) => s + g.rows.length, 0);

  // Hlavička soupisu.
  doc.fontSize(15).text('Soupis práce', { underline: true });
  doc.moveDown(0.3);
  doc.fontSize(9);
  doc.text(`Zakázka: ${worksheet.job.projectNumber} – ${worksheet.job.name}`);
  doc.text(`Stav: ${STATUS_LABELS[worksheet.status]}    Období: ${periodFrom} – ${periodTo}`);
  doc.text(`Pracovníci: ${workerNames || '—'}    Počet položek: ${itemCount}`);
  // Horní souhrnná fakturační tabulka + odsouhlasovací text.
  doc.text(`Celková cena bez DPH: ${money(total)}`);
  doc.moveDown(0.3);
  doc
    .fontSize(8)
    .text(
      'Odsouhlasením tohoto soupisu objednatel potvrzuje provedení uvedených prací v daném rozsahu a cenách.',
    );
  doc.moveDown(0.5);

  const rowPadX = 3;
  const headerFontSize = 8;
  const bodyFontSize = 7.5;

  function cellText(col: (typeof EXPORT_COLUMNS)[number], row: ExportRowLike): string {
    const v = (row as Record<string, unknown>)[col.key];
    if (col.money) return money(v as number | null);
    return String(v ?? '');
  }

  function rowHeight(cells: string[]): number {
    let max = 14;
    EXPORT_COLUMNS.forEach((col, i) => {
      const h =
        doc.heightOfString(cells[i] ?? '', { width: colWidths[i] - rowPadX * 2 }) + 6;
      if (h > max) max = h;
    });
    return max;
  }

  function drawRow(cells: string[], opts: { header?: boolean; bold?: boolean }) {
    const h = rowHeight(cells);
    if (doc.y + h > bottomY) {
      doc.addPage();
      drawHeaderRow();
    }
    const y = doc.y;
    let x = margin;
    if (opts.header || opts.bold) setCzechPdfBold(doc);
    else setCzechPdfRegular(doc);
    EXPORT_COLUMNS.forEach((col, i) => {
      const w = colWidths[i];
      doc.rect(x, y, w, h).stroke();
      doc.fontSize(opts.header ? headerFontSize : bodyFontSize);
      doc.text(cells[i] ?? '', x + rowPadX, y + 3, {
        width: w - rowPadX * 2,
        align: col.align,
      });
      x += w;
    });
    setCzechPdfRegular(doc);
    doc.y = y + h;
  }

  function drawHeaderRow() {
    drawRow(
      EXPORT_COLUMNS.map((c) => c.label),
      { header: true },
    );
  }

  drawHeaderRow();
  for (const group of floorGroups) {
    for (const row of group.rows) {
      drawRow(
        EXPORT_COLUMNS.map((c) => cellText(c, row)),
        {},
      );
    }
    // Součet za podlaží (tučně, cena vpravo).
    const floorTotalCells = EXPORT_COLUMNS.map(() => '');
    floorTotalCells[0] = `Cena za podlaží – ${group.floorName}`;
    floorTotalCells[EXPORT_COLUMNS.length - 1] = money(group.floorTotal);
    drawRow(floorTotalCells, { bold: true });
  }

  doc.moveDown(0.6);
  setCzechPdfBold(doc);
  doc.fontSize(11).text(`Cena celkem bez DPH: ${money(total)}`);
  setCzechPdfRegular(doc);
  doc.fontSize(9).text(`Datum: ${new Date().toISOString().split('T')[0]}`);
  doc.end();
}

type ExportRowLike = Record<string, unknown>;

export { STATUS_LABELS };
