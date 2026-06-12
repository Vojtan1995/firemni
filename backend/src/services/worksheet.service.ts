import { WorkSheetStatus, UserRole, SealStatus } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';
import { hasPermission } from '../lib/permissions.js';
import { logActivity, logChange } from './audit.service.js';
import { notifyUsersByRoles, createNotification } from './notification.service.js';
import { csvWithBom } from '../lib/csv-export.js';
import { createCzechPdfDocument, writePdfTextLine } from '../lib/pdf-pagination.js';

const STATUS_TRANSITIONS: Record<WorkSheetStatus, WorkSheetStatus[]> = {
  [WorkSheetStatus.draft]: [WorkSheetStatus.submitted],
  [WorkSheetStatus.submitted]: [WorkSheetStatus.reviewed, WorkSheetStatus.draft],
  [WorkSheetStatus.reviewed]: [
    WorkSheetStatus.ready_for_invoice,
    WorkSheetStatus.submitted,
    WorkSheetStatus.draft,
  ],
  [WorkSheetStatus.ready_for_invoice]: [WorkSheetStatus.invoiced, WorkSheetStatus.reviewed],
  [WorkSheetStatus.invoiced]: [WorkSheetStatus.ready_for_invoice],
};

const UCETNI_TRANSITIONS: Array<[WorkSheetStatus, WorkSheetStatus]> = [
  [WorkSheetStatus.reviewed, WorkSheetStatus.ready_for_invoice],
  [WorkSheetStatus.ready_for_invoice, WorkSheetStatus.invoiced],
  [WorkSheetStatus.invoiced, WorkSheetStatus.ready_for_invoice],
];

const STATUS_LABELS: Record<WorkSheetStatus, string> = {
  [WorkSheetStatus.draft]: 'Rozpracovaný',
  [WorkSheetStatus.submitted]: 'Odevzdaný',
  [WorkSheetStatus.reviewed]: 'Zkontrolovaný',
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

  if (role === UserRole.ucetni) {
    const allowed = UCETNI_TRANSITIONS.some(([from, to]) => from === current && to === next);
    if (!allowed) {
      throw forbidden('Administrativa může měnit pouze fakturační stavy soupisu');
    }
    if (!hasPermission(role, 'worksheet.invoice')) {
      throw forbidden('Nemáte oprávnění měnit fakturační stav soupisu');
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
    include: { workers: { select: { userId: true } } },
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
    orderBy: { updatedAt: 'desc' },
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
      items: { orderBy: { sortOrder: 'asc' } },
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

  const entries = await prisma.sealEntry.findMany({
    where: { id: { in: sealEntryIds }, deletedAt: null },
    include: {
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
  const created = await prisma.$transaction(
    entries.map((entry, i) => {
      const unitPrice = entry.unitPrice;
      const quantity = entry.quantity;
      const totalPrice =
        entry.totalPrice ??
        (unitPrice != null ? Number(unitPrice) * Number(quantity) : null);
      return prisma.workSheetItem.create({
        data: {
          worksheetId,
          sealId: entry.sealId,
          sealEntryId: entry.id,
          floorId: entry.seal.floorId,
          workerId: entry.seal.createdById,
          sealNumber: entry.seal.sealNumber,
          entryType: entry.entryType,
          dimension: entry.dimension,
          quantity,
          unit: entry.unit ?? 'kus',
          unitPrice,
          totalPrice,
          sortOrder: existingCount + i,
        },
      });
    }),
  );

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
    await notifyUsersByRoles([UserRole.vedeni, UserRole.ucetni, UserRole.admin], {
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
  filters: { floorIds?: string[]; status?: string; from?: string; to?: string },
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

  const entries = await prisma.sealEntry.findMany({
    where: { deletedAt: null, seal: sealWhere },
    select: { id: true },
  });

  return addWorksheetItems(
    worksheetId,
    role,
    userId,
    entries.map((e) => e.id),
  );
}

type WorksheetExportRow = Record<string, string | number | null>;

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

  const rows: WorksheetExportRow[] = worksheet.items.map((item) => ({
    stavba: worksheet.job.projectNumber,
    nazevStavby: worksheet.job.name,
    patro: String(floorMap.get(item.floorId) ?? item.floorId),
    cisloUcpavky: item.sealNumber,
    typProstupu: item.entryType,
    rozmery: item.dimension,
    jednotka: item.unit ?? 'kus',
    mnozstvi: Number(item.quantity),
    kusy: Number(item.quantity),
    pracovnik: workerMap.get(item.workerId) ?? '',
    jednotkovaCena: item.unitPrice != null ? Number(item.unitPrice) : null,
    cenaCelkem: item.totalPrice != null ? Number(item.totalPrice) : null,
  }));

  return { worksheet, rows, total: sumItemTotals(worksheet.items) };
}

const CSV_COLUMNS: Record<string, string> = {
  stavba: 'Stavba',
  nazevStavby: 'Název stavby',
  patro: 'Podlaží',
  cisloUcpavky: 'Prostup',
  typProstupu: 'Typ',
  rozmery: 'Rozměr',
  jednotka: 'Jednotka',
  mnozstvi: 'Množství',
  kusy: 'Počet',
  pracovnik: 'Provedl',
  jednotkovaCena: 'Jednotková cena',
  cenaCelkem: 'Cena celkem',
};

export async function exportWorksheetCsv(id: string, role: UserRole, userId: string) {
  const { worksheet, rows, total } = await loadWorksheetExportData(id, role, userId);
  const cols = Object.keys(CSV_COLUMNS);
  const header = cols.map((c) => CSV_COLUMNS[c]).join(';');
  const lines = rows.map((row) =>
    cols.map((c) => `"${String(row[c] ?? '').replace(/"/g, '""')}"`).join(';'),
  );
  const footer = `"Součet bez DPH";"";"";"";"";"";"";"";"${total.toFixed(2)}"`;
  const csv = csvWithBom([header, ...lines, footer].join('\n'));
  const filename = `soupis-${worksheet.job.projectNumber}-${worksheet.id.slice(0, 8)}.csv`;
  return { csv, filename };
}

export async function exportWorksheetPdf(
  id: string,
  role: UserRole,
  userId: string,
  res: import('express').Response,
) {
  const { worksheet, rows, total } = await loadWorksheetExportData(id, role, userId);

  const filename = `soupis-${worksheet.job.projectNumber}-${worksheet.id.slice(0, 8)}.pdf`;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

  const doc = createCzechPdfDocument({ margin: 40, size: 'A4' });
  doc.pipe(res);

  const periodFrom = worksheet.periodFrom?.toISOString().split('T')[0] ?? '—';
  const periodTo = worksheet.periodTo?.toISOString().split('T')[0] ?? '—';
  const workerNames = worksheet.workers.map((w) => w.user.displayName).join(', ');

  doc.fontSize(16).text('Soupis práce', { underline: true });
  doc.moveDown(0.5);
  doc.fontSize(10);
  doc.text(`Zakázka: ${worksheet.job.projectNumber} – ${worksheet.job.name}`);
  doc.text(`Stav: ${STATUS_LABELS[worksheet.status]}`);
  doc.text(`Období: ${periodFrom} – ${periodTo}`);
  doc.text(`Pracovníci: ${workerNames || '—'}`);
  doc.text(`Počet položek: ${rows.length}`);
  doc.text(`Vytvořeno: ${worksheet.createdAt.toISOString().split('T')[0]}`);
  doc.moveDown();

  doc.fontSize(8);
  for (const row of rows) {
    const unitPrice =
      row.jednotkovaCena != null ? `${Number(row.jednotkovaCena).toFixed(2)} Kč` : '—';
    const line = row.cenaCelkem != null ? `${Number(row.cenaCelkem).toFixed(2)} Kč` : '—';
    const qtyUnit = `${row.mnozstvi} ${row.jednotka ?? 'kus'}`;
    writePdfTextLine(
      doc,
      `#${row.cisloUcpavky} | ${row.patro} | ${row.typProstupu} | ${row.rozmery} | ${qtyUnit} | ${unitPrice} | ${line} | ${row.pracovnik}`,
    );
  }

  doc.moveDown();
  doc.fontSize(12).text(`Cena celkem bez DPH: ${total.toFixed(2)} Kč`, { underline: true });
  doc.end();
}

export { STATUS_LABELS };
