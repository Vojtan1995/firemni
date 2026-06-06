import { Router, Request, Response, NextFunction } from 'express';
import PDFDocument from 'pdfkit';
import { SealStatus, UserRole } from '@prisma/client';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { requirePermission } from '../lib/permissions.js';
import { prisma } from '../lib/prisma.js';
import * as jobParticipantService from '../services/job-participant.service.js';

const router = Router();
router.use(authMiddleware);
router.use(requirePermission('reports.view', 'reports.export'));

function applyWorkerReportScope(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role === UserRole.worker) {
    req.query.workerId = req.user.id;
  }
  next();
}

router.use(applyWorkerReportScope);

function buildWhere(query: Record<string, unknown>) {
  const where: Record<string, unknown> = { deletedAt: null };
  if (query.jobId) where.jobId = String(query.jobId);
  if (query.status) where.status = String(query.status) as SealStatus;
  if (query.workerId) where.createdById = String(query.workerId);
  if (query.floorId) where.floorId = String(query.floorId);
  if (query.system) where.system = String(query.system);
  if (query.from || query.to) {
    where.createdAt = {};
    if (query.from) (where.createdAt as Record<string, Date>).gte = new Date(String(query.from));
    if (query.to) (where.createdAt as Record<string, Date>).lte = new Date(String(query.to));
  }
  return where;
}

type SummaryRow = Record<string, string | number | null>;

async function fetchSummaryRows(query: Record<string, unknown>) {
  const sealWhere = buildWhere(query);
  const entryType = query.entryType ? String(query.entryType) : undefined;
  const material = query.material ? String(query.material) : undefined;

  const seals = await prisma.seal.findMany({
    where: sealWhere,
    include: {
      job: true,
      floor: true,
      createdBy: { select: { displayName: true } },
      entries: {
        where: {
          deletedAt: null,
          ...(entryType ? { entryType } : {}),
        },
        include: {
          materials: {
            where: material ? { material: { contains: material, mode: 'insensitive' } } : undefined,
            orderBy: { sortOrder: 'asc' },
          },
          priceListItem: { select: { sizeLabel: true, category: true } },
        },
        orderBy: { sortOrder: 'asc' },
      },
    },
    orderBy: [{ jobId: 'asc' }, { floorId: 'asc' }, { sealNumber: 'asc' }],
  });

  const rows: SummaryRow[] = [];
  for (const seal of seals) {
    for (const entry of seal.entries) {
      if (entry.materials.length === 0 && material) continue;
      const mats = entry.materials.map((m) => m.material).join(', ');
      const unitPrice = entry.unitPrice != null ? Number(entry.unitPrice) : null;
      const totalPrice = entry.totalPrice != null ? Number(entry.totalPrice) : null;
      rows.push({
        stavba: seal.job.projectNumber,
        nazevStavby: seal.job.name,
        patro: seal.floor.name,
        cisloUcpavky: seal.sealNumber,
        status: seal.status,
        system: seal.system,
        typProstupu: entry.entryType,
        rozmery: entry.dimension,
        kusy: Number(entry.quantity),
        izolace: entry.insulation,
        umisteni: seal.location,
        materialy: mats,
        katalogId: mats,
        pracovnik: seal.createdBy.displayName,
        datum: seal.createdAt.toISOString().split('T')[0],
        jednotkovaCena: unitPrice,
        cenaCelkem: totalPrice,
        cenaVerze: entry.priceListVersion,
        interniPoznamka: seal.internalNote,
      });
    }
  }
  return rows;
}

function sumRows(rows: SummaryRow[]) {
  return rows.reduce((acc, row) => acc + (Number(row.cenaCelkem) || 0), 0);
}

function groupByFloor(rows: SummaryRow[]) {
  const groups = new Map<string, SummaryRow[]>();
  for (const row of rows) {
    const key = String(row.patro);
    const list = groups.get(key) ?? [];
    list.push(row);
    groups.set(key, list);
  }
  return groups;
}

router.get('/filter-options', async (req, res, next) => {
  try {
    const role = req.user!.role;
    const userId = req.user!.id;

    let jobs: { id: string; projectNumber: string; name: string }[];
    if (role === UserRole.worker) {
      const myJobs = await jobParticipantService.listMyJobs(userId);
      jobs = myJobs.map((j) => ({
        id: j.id,
        projectNumber: j.projectNumber,
        name: j.name,
      }));
    } else {
      jobs = await prisma.job.findMany({
        where: { deletedAt: null, isArchived: false },
        select: { id: true, projectNumber: true, name: true },
        orderBy: { createdAt: 'desc' },
      });
    }

    const workers =
      role === UserRole.worker
        ? []
        : await prisma.user.findMany({
            where: { role: UserRole.worker, isActive: true },
            select: { id: true, displayName: true },
            orderBy: { displayName: 'asc' },
          });

    res.json({ jobs, workers });
  } catch (e) {
    next(e);
  }
});

router.get('/work-summary', async (req, res, next) => {
  try {
    const rows = await fetchSummaryRows(req.query as Record<string, unknown>);
    const total = sumRows(rows);
    res.json({ count: rows.length, totalCzk: total, rows });
  } catch (e) {
    next(e);
  }
});

const CSV_COLUMNS: Record<string, string> = {
  stavba: 'Stavba',
  nazevStavby: 'Název stavby',
  patro: 'Podlaží',
  cisloUcpavky: 'Prostup',
  status: 'Status',
  system: 'Systém',
  katalogId: 'Katalog ID',
  typProstupu: 'Typ',
  rozmery: 'Rozměr',
  kusy: 'Počet',
  izolace: 'Izolace',
  umisteni: 'Umístění v PÚ',
  pracovnik: 'Provedl',
  jednotkovaCena: 'Jednotková cena',
  cenaCelkem: 'Cena celkem',
  cenaVerze: 'Ceník verze',
  materialy: 'Materiály',
  datum: 'Datum',
  interniPoznamka: 'Interní poznámka',
};

router.get('/export/csv', async (req, res, next) => {
  try {
    const rows = await fetchSummaryRows(req.query as Record<string, unknown>);
    const colsParam = req.query.columns ? String(req.query.columns).split(',') : Object.keys(CSV_COLUMNS);
    const cols = colsParam.filter((c) => CSV_COLUMNS[c]);

    const header = cols.map((c) => CSV_COLUMNS[c]).join(';');
    const lines = rows.map((row) =>
      cols.map((c) => `"${String(row[c] ?? '').replace(/"/g, '""')}"`).join(';'),
    );

    const total = sumRows(rows);
    const footer = `"Součet bez DPH";"";"";"";"";"";"";"";"";"";"";"";"";"";"";"${total.toFixed(2)}"`;

    const bom = '\uFEFF';
    const csv = bom + [header, ...lines, footer].join('\n');

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="soupis-praci.csv"');
    res.send(csv);
  } catch (e) {
    next(e);
  }
});

router.get('/export/pdf', async (req, res, next) => {
  try {
    const query = req.query as Record<string, unknown>;
    const rows = await fetchSummaryRows(query);
    const total = sumRows(rows);
    const floorGroups = groupByFloor(rows);

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename="soupis-praci.pdf"');

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    doc.pipe(res);

    const jobLabel = rows[0]?.stavba ? String(rows[0].stavba) : '—';
    const jobName = rows[0]?.nazevStavby ? String(rows[0].nazevStavby) : '—';
    const periodFrom = query.from ? String(query.from) : '—';
    const periodTo = query.to ? String(query.to) : '—';

    doc.fontSize(16).text('Soupis prací', { underline: true });
    doc.moveDown(0.5);
    doc.fontSize(10);
    doc.text(`Zakázka: ${jobLabel} – ${jobName}`);
    doc.text(`Období: ${periodFrom} – ${periodTo}`);
    doc.text(`Počet řádků: ${rows.length}`);
    doc.moveDown();

    for (const [floor, floorRows] of floorGroups) {
      doc.fontSize(12).text(`Podlaží: ${floor}`, { underline: true });
      doc.moveDown(0.3);
      doc.fontSize(8);

      for (const row of floorRows.slice(0, 500)) {
        const unit = row.jednotkovaCena != null ? `${Number(row.jednotkovaCena).toFixed(2)} Kč` : '—';
        const line = row.cenaCelkem != null ? `${Number(row.cenaCelkem).toFixed(2)} Kč` : '—';
        doc.text(
          `#${row.cisloUcpavky} | ${row.typProstupu} | ${row.rozmery} | ${row.kusy} ks | Katalog: ${row.katalogId} | ${unit} | ${line} | ${row.pracovnik}`,
        );
      }

      const floorTotal = sumRows(floorRows);
      doc.moveDown(0.3);
      doc.fontSize(10).text(`Cena za podlaží ${floor}: ${floorTotal.toFixed(2)} Kč bez DPH`);
      doc.moveDown();
    }

    doc.fontSize(12).text(`Cena celkem bez DPH: ${total.toFixed(2)} Kč`, { underline: true });
    doc.end();
  } catch (e) {
    next(e);
  }
});

export default router;
