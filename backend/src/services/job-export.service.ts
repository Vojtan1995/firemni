import sharp from 'sharp';
import { JobStatus, SealStatus, UserRole } from '@prisma/client';
import type { Response } from 'express';
import { prisma } from '../lib/prisma.js';
import { notFound } from '../lib/errors.js';
import {
  JOB_EXPORT_HISTORY_LIMIT,
  JOB_EXPORT_PHOTO_THUMB_LIMIT,
  JOB_EXPORT_PHOTOS_PER_SEAL,
  JOB_EXPORT_SEAL_LIMIT,
} from '../lib/limits.js';
import { csvWithBom } from '../lib/csv-export.js';
import { createCzechPdfDocument, writePdfHeading, writePdfTextLine } from '../lib/pdf-pagination.js';
import { anonymizeUserForViewer } from '../lib/user-privacy.js';
import { assertJobReadable } from './authorization.service.js';
import { getObjectStorage } from './storage.service.js';
import { STATUS_LABELS } from './worksheet.service.js';

const SEAL_STATUS_LABELS: Record<SealStatus, string> = {
  [SealStatus.draft]: 'Rozpracováno',
  [SealStatus.checked]: 'Zkontrolováno',
  [SealStatus.invoiced]: 'Fakturováno',
};

const JOB_STATUS_LABELS: Record<JobStatus, string> = {
  [JobStatus.active]: 'Aktivní',
  [JobStatus.completed]: 'Dokončeno',
  [JobStatus.archived]: 'Archivováno',
};

function csvEscape(value: unknown) {
  return `"${String(value ?? '').replace(/"/g, '""')}"`;
}

function csvRow(cells: unknown[]) {
  return cells.map(csvEscape).join(';');
}

function workerScope(role: UserRole, userId: string) {
  return role === UserRole.worker ? { createdById: userId } : {};
}

function includeInternalNotes(role: UserRole) {
  return role === UserRole.vedeni || role === UserRole.admin;
}

async function loadJobExportData(jobId: string, role: UserRole, userId: string) {
  await assertJobReadable(jobId, role, userId);

  const job = await prisma.job.findFirst({
    where: { id: jobId, deletedAt: null },
    include: {
      floors: { where: { deletedAt: null }, orderBy: { sortOrder: 'asc' } },
    },
  });
  if (!job) throw notFound('Stavba nenalezena');

  const sealWhere = {
    jobId,
    deletedAt: null,
    ...workerScope(role, userId),
  };

  const seals = await prisma.seal.findMany({
    where: sealWhere,
    include: {
      floor: { select: { name: true, sortOrder: true } },
      createdBy: { select: { id: true, displayName: true, role: true } },
      entries: {
        where: { deletedAt: null },
        include: { materials: { orderBy: { sortOrder: 'asc' } } },
        orderBy: { sortOrder: 'asc' },
      },
      photos: { orderBy: { createdAt: 'asc' }, take: JOB_EXPORT_PHOTOS_PER_SEAL },
      _count: { select: { photos: true } },
    },
    orderBy: [{ floorId: 'asc' }, { sealNumber: 'asc' }],
    take: JOB_EXPORT_SEAL_LIMIT,
  });

  const statusBreakdown = await prisma.seal.groupBy({
    by: ['status'],
    where: sealWhere,
    _count: { id: true },
  });

  const worksheetWhere =
    role === UserRole.worker
      ? { jobId, workers: { some: { userId } } }
      : { jobId };

  const worksheets = await prisma.workSheet.findMany({
    where: worksheetWhere,
    include: {
      workers: { include: { user: { select: { displayName: true } } } },
      _count: { select: { items: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 100,
  });

  const sealIds = seals.map((s) => s.id);
  const [activities, changes] = await Promise.all([
    prisma.activityLog.findMany({
      where: {
        OR: [
          { entityType: 'job', entityId: jobId },
          ...(sealIds.length ? [{ entityType: 'seal', entityId: { in: sealIds } }] : []),
        ],
      },
      include: { user: { select: { displayName: true, username: true, role: true } } },
      orderBy: { createdAt: 'desc' },
      take: JOB_EXPORT_HISTORY_LIMIT,
    }),
    prisma.changeLog.findMany({
      where: { entityType: 'seal', entityId: { in: sealIds } },
      include: { user: { select: { displayName: true, role: true } } },
      orderBy: { createdAt: 'desc' },
      take: JOB_EXPORT_HISTORY_LIMIT,
    }),
  ]);

  return { job, seals, statusBreakdown, worksheets, activities, changes };
}

function sealNoteForExport(
  seal: { note: string | null; internalNote: string | null },
  role: UserRole,
) {
  const parts = [seal.note?.trim()].filter(Boolean);
  if (includeInternalNotes(role) && seal.internalNote?.trim()) {
    parts.push(`[interní] ${seal.internalNote.trim()}`);
  }
  return parts.join(' | ');
}

function workerLabel(
  user: { id: string; displayName: string; role: UserRole },
  viewerRole: UserRole,
) {
  return anonymizeUserForViewer(user, viewerRole).displayName;
}

export async function exportJobCsv(jobId: string, role: UserRole, userId: string) {
  const { job, seals, statusBreakdown, worksheets, activities, changes } =
    await loadJobExportData(jobId, role, userId);

  const lines: string[] = [];
  const pushSection = (title: string, header: string[], rows: unknown[][]) => {
    lines.push('');
    lines.push(csvRow([title]));
    lines.push(header.map(csvEscape).join(';'));
    for (const row of rows) lines.push(csvRow(row));
  };

  lines.push(csvRow(['Export zakázky']));
  lines.push(
    csvRow(['Číslo stavby', job.projectNumber, 'Název', job.name, 'Stav', JOB_STATUS_LABELS[job.status]]),
  );
  if (job.address) lines.push(csvRow(['Adresa', job.address]));
  if (job.note) lines.push(csvRow(['Poznámka stavby', job.note]));
  lines.push(csvRow(['Exportováno', new Date().toISOString().split('T')[0]]));

  pushSection(
    'Přehled stavů ucpávek',
    ['Stav', 'Počet'],
    statusBreakdown.map((s) => [SEAL_STATUS_LABELS[s.status], s._count.id]),
  );

  pushSection(
    'Ucpávky',
    [
      'Patro',
      'Číslo',
      'Stav',
      'Systém',
      'Umístění',
      'Požární odolnost',
      'Fotek',
      'Pracovník',
      'Poznámka',
      'Typ prostupu',
      'Rozměr',
      'Kusy',
      'Materiály',
      'Cena celkem',
    ],
    seals.flatMap((seal) => {
      const base = [
        seal.floor.name,
        seal.sealNumber,
        SEAL_STATUS_LABELS[seal.status],
        seal.system,
        seal.location,
        seal.fireRating,
        seal._count.photos,
        workerLabel(seal.createdBy, role),
        sealNoteForExport(seal, role),
      ];
      if (seal.entries.length === 0) {
        return [[...base, '', '', '', '', '']];
      }
      return seal.entries.map((entry, idx) => [
        ...(idx === 0 ? base : ['', '', '', '', '', '', '', '', '']),
        entry.entryType,
        entry.dimension,
        Number(entry.quantity),
        entry.materials.map((m) => m.material).join(', '),
        entry.totalPrice != null ? Number(entry.totalPrice).toFixed(2) : '',
      ]);
    }),
  );

  pushSection(
    'Soupisy práce',
    ['ID', 'Stav', 'Období od', 'Období do', 'Pracovníci', 'Položek', 'Poznámka'],
    worksheets.map((ws) => [
      ws.id.slice(0, 8),
      STATUS_LABELS[ws.status],
      ws.periodFrom?.toISOString().split('T')[0] ?? '',
      ws.periodTo?.toISOString().split('T')[0] ?? '',
      ws.workers.map((w) => w.user.displayName).join(', '),
      ws._count.items,
      ws.note ?? '',
    ]),
  );

  const historyRows = [
    ...activities.map((a) => [
      a.createdAt.toISOString(),
      'aktivita',
      a.action,
      a.entityType ?? '',
      a.entityId?.slice(0, 8) ?? '',
      anonymizeUserForViewer(
        { id: a.userId, displayName: a.user.displayName, role: a.user.role },
        role,
      ).displayName,
    ]),
    ...changes.map((c) => [
      c.createdAt.toISOString(),
      'změna',
      c.fieldName,
      'seal',
      c.entityId.slice(0, 8),
      anonymizeUserForViewer(
        { id: c.userId, displayName: c.user.displayName, role: c.user.role },
        role,
      ).displayName,
      `${c.oldValue ?? ''} → ${c.newValue ?? ''}`,
    ]),
  ]
    .sort((a, b) => String(b[0]).localeCompare(String(a[0])))
    .slice(0, JOB_EXPORT_HISTORY_LIMIT);

  pushSection(
    'Historie (výběr)',
    ['Čas', 'Typ', 'Akce/pole', 'Entita', 'ID', 'Uživatel', 'Detail'],
    historyRows.map((row) => {
      const copy = [...row];
      while (copy.length < 7) copy.push('');
      return copy.slice(0, 7);
    }),
  );

  const csv = csvWithBom(lines.join('\n'));
  const filename = `zakazka-${job.projectNumber}.csv`;
  return { csv, filename };
}

async function loadPhotoThumb(filePath: string): Promise<Buffer | null> {
  try {
    const storage = getObjectStorage();
    if (!(await storage.exists(filePath))) return null;
    const raw = await storage.get(filePath);
    return sharp(raw).rotate().resize(140, 140, { fit: 'inside' }).jpeg({ quality: 70 }).toBuffer();
  } catch {
    return null;
  }
}

export async function exportJobPdf(
  jobId: string,
  role: UserRole,
  userId: string,
  res: Response,
) {
  const { job, seals, statusBreakdown, worksheets, activities, changes } =
    await loadJobExportData(jobId, role, userId);

  const filename = `zakazka-${job.projectNumber}.pdf`;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

  const doc = createCzechPdfDocument({ margin: 40, size: 'A4' });
  doc.pipe(res);

  doc.fontSize(18).text('Export zakázky', { underline: true });
  doc.moveDown(0.5);
  doc.fontSize(10);
  doc.text(`Stavba: ${job.projectNumber} – ${job.name}`);
  doc.text(`Stav zakázky: ${JOB_STATUS_LABELS[job.status]}`);
  if (job.address) doc.text(`Adresa: ${job.address}`);
  if (job.note) doc.text(`Poznámka: ${job.note}`);
  doc.text(`Počet ucpávek: ${seals.length}`);
  doc.text(`Export: ${new Date().toISOString().split('T')[0]}`);
  doc.moveDown();

  writePdfHeading(doc, 'Přehled stavů');
  for (const row of statusBreakdown) {
    writePdfTextLine(doc, `${SEAL_STATUS_LABELS[row.status]}: ${row._count.id}`);
  }
  doc.moveDown();

  const floors = [...job.floors].sort((a, b) => a.sortOrder - b.sortOrder);
  for (const floor of floors) {
    const floorSeals = seals.filter((s) => s.floorId === floor.id);
    if (floorSeals.length === 0) continue;

    writePdfHeading(doc, `Patro: ${floor.name} (${floorSeals.length} ucpávek)`);
    doc.fontSize(8);
    for (const seal of floorSeals) {
      const note = sealNoteForExport(seal, role);
      const notePart = note ? ` | Pozn.: ${note.slice(0, 100)}${note.length > 100 ? '…' : ''}` : '';
      writePdfTextLine(
        doc,
        `#${seal.sealNumber} | ${SEAL_STATUS_LABELS[seal.status]} | ${seal.system} | ${seal.location} | Fotek: ${seal._count.photos} | ${workerLabel(seal.createdBy, role)}${notePart}`,
      );
      for (const entry of seal.entries) {
        const mats = entry.materials.map((m) => m.material).join(', ');
        const price =
          entry.totalPrice != null ? ` | ${Number(entry.totalPrice).toFixed(2)} Kč` : '';
        writePdfTextLine(
          doc,
          `  → ${entry.entryType} ${entry.dimension} × ${Number(entry.quantity)} | ${mats}${price}`,
        );
      }
    }
    doc.moveDown(0.5);
  }

  if (worksheets.length > 0) {
    writePdfHeading(doc, 'Soupisy práce');
    doc.fontSize(8);
    for (const ws of worksheets) {
      const from = ws.periodFrom?.toISOString().split('T')[0] ?? '—';
      const to = ws.periodTo?.toISOString().split('T')[0] ?? '—';
      writePdfTextLine(
        doc,
        `${ws.id.slice(0, 8)} | ${STATUS_LABELS[ws.status]} | ${from} – ${to} | ${ws._count.items} položek | ${ws.workers.map((w) => w.user.displayName).join(', ')}`,
      );
    }
    doc.moveDown();
  }

  writePdfHeading(doc, 'Historie (výběr)');
  doc.fontSize(8);
  const history = [
    ...activities.map((a) => ({
      at: a.createdAt,
      line: `${a.createdAt.toISOString().split('T')[0]} | ${a.action} | ${a.entityType ?? ''} | ${anonymizeUserForViewer({ id: a.userId, displayName: a.user.displayName, role: a.user.role }, role).displayName}`,
    })),
    ...changes.map((c) => ({
      at: c.createdAt,
      line: `${c.createdAt.toISOString().split('T')[0]} | změna ${c.fieldName} | ${c.oldValue ?? '—'} → ${c.newValue ?? '—'} | ${anonymizeUserForViewer({ id: c.userId, displayName: c.user.displayName, role: c.user.role }, role).displayName}`,
    })),
  ]
    .sort((a, b) => b.at.getTime() - a.at.getTime())
    .slice(0, JOB_EXPORT_HISTORY_LIMIT);

  for (const item of history) {
    writePdfTextLine(doc, item.line);
  }

  const photosToRender: Array<{ sealNumber: string; buffer: Buffer }> = [];
  for (const seal of seals) {
    for (const photo of seal.photos) {
      if (photosToRender.length >= JOB_EXPORT_PHOTO_THUMB_LIMIT) break;
      const buffer = await loadPhotoThumb(photo.filePath);
      if (buffer) photosToRender.push({ sealNumber: seal.sealNumber, buffer });
    }
    if (photosToRender.length >= JOB_EXPORT_PHOTO_THUMB_LIMIT) break;
  }

  if (photosToRender.length > 0) {
    doc.addPage();
    writePdfHeading(doc, `Fotodokumentace (náhledy, max ${JOB_EXPORT_PHOTO_THUMB_LIMIT})`);
    const thumbW = 110;
    const thumbH = 110;
    const gap = 12;
    const startX = 40;
    let x = startX;
    let y = doc.y + 8;
    const rowBottom = 700;

    for (const item of photosToRender) {
      if (x + thumbW > 555) {
        x = startX;
        y += thumbH + 28;
      }
      if (y + thumbH > rowBottom) {
        doc.addPage();
        y = 60;
        x = startX;
      }
      doc.image(item.buffer, x, y, { width: thumbW, height: thumbH, fit: [thumbW, thumbH] });
      doc.fontSize(7).text(`#${item.sealNumber}`, x, y + thumbH + 2, { width: thumbW, align: 'center' });
      x += thumbW + gap;
    }
  }

  doc.end();
}
