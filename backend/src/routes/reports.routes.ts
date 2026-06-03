import { Router } from 'express';
import PDFDocument from 'pdfkit';
import { SealStatus, UserRole } from '@prisma/client';
import { authMiddleware, requireRole } from '../middleware/auth.middleware.js';
import { prisma } from '../lib/prisma.js';

const router = Router();
router.use(authMiddleware);
router.use(requireRole(UserRole.management, UserRole.admin));

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
          },
        },
      },
    },
    orderBy: [{ jobId: 'asc' }, { sealNumber: 'asc' }],
  });

  const rows: Array<Record<string, string | number>> = [];
  for (const seal of seals) {
    for (const entry of seal.entries) {
      if (entry.materials.length === 0 && material) continue;
      const mats = entry.materials.map((m) => m.material).join(', ');
      rows.push({
        stavba: seal.job.projectNumber,
        nazevStavby: seal.job.name,
        patro: seal.floor.name,
        cisloUcpavky: seal.sealNumber,
        status: seal.status,
        system: seal.system,
        typProstupu: entry.entryType,
        rozmery: entry.dimension,
        kusy: entry.quantity,
        materialy: mats,
        pracovnik: seal.createdBy.displayName,
        datum: seal.createdAt.toISOString().split('T')[0],
      });
    }
  }
  return rows;
}

router.get('/work-summary', async (req, res, next) => {
  try {
    const rows = await fetchSummaryRows(req.query as Record<string, unknown>);
    res.json({ count: rows.length, rows });
  } catch (e) {
    next(e);
  }
});

const CSV_COLUMNS: Record<string, string> = {
  stavba: 'Stavba',
  nazevStavby: 'Název stavby',
  patro: 'Patro',
  cisloUcpavky: 'Číslo ucpávky',
  status: 'Status',
  system: 'Systém',
  typProstupu: 'Typ prostupu',
  rozmery: 'Rozměry',
  kusy: 'Kusy',
  materialy: 'Materiály',
  pracovnik: 'Pracovník',
  datum: 'Datum',
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

    const bom = '\uFEFF';
    const csv = bom + [header, ...lines].join('\n');

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="soupis-praci.csv"');
    res.send(csv);
  } catch (e) {
    next(e);
  }
});

router.get('/export/pdf', async (req, res, next) => {
  try {
    const rows = await fetchSummaryRows(req.query as Record<string, unknown>);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename="soupis-praci.pdf"');

    const doc = new PDFDocument({ margin: 40 });
    doc.pipe(res);
    doc.fontSize(16).text('Soupis prací', { underline: true });
    doc.moveDown();
    doc.fontSize(10);

    for (const row of rows.slice(0, 500)) {
      doc.text(
        `${row.stavba} | ${row.patro} | #${row.cisloUcpavky} | ${row.typProstupu} | ${row.kusy} ks | ${row.materialy}`,
      );
    }
    doc.end();
  } catch (e) {
    next(e);
  }
});

export default router;
