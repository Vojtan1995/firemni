import path from 'path';
import sharp from 'sharp';
import { pdf as pdfToImg } from 'pdf-to-img';
import { UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';
import { hasPermission } from '../lib/permissions.js';
import {
  assertFloorReadable,
  assertJobWritable,
  assertSealReadable,
} from './authorization.service.js';
import { assertSealEditable } from './seal.service.js';
import { getObjectStorage, sanitizeObjectKey } from './storage.service.js';
import { logActivity } from './audit.service.js';

const maxDrawingBytes = 25 * 1024 * 1024;

/** Max. doba na render/parsování PDF stránky — chrání před zaseknutím requestu
 *  (a vyčerpáním connection poolu) na poškozeném/obřím PDF. */
const pdfParseTimeoutMs = 20_000;

/** Obalí promise timeoutem; po vypršení rejectuje `badRequest(message)`.
 *  Timer se vždy uklidí, aby nedržel event loop. */
function withTimeout<T>(promise: Promise<T>, ms: number, message: string): Promise<T> {
  let timer: NodeJS.Timeout;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(badRequest(message)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function clamp01(value: number) {
  if (!Number.isFinite(value)) throw badRequest('Souřadnice musí být číslo');
  return Math.min(1, Math.max(0, value));
}

function resolveDrawingMimeAndExt(
  mimetype: string,
  originalname: string,
): { mimeType: string; ext: string } {
  const normalized = mimetype.toLowerCase();
  if (normalized === 'application/pdf') {
    return { mimeType: 'application/pdf', ext: 'pdf' };
  }
  if (normalized === 'image/png') {
    return { mimeType: 'image/png', ext: 'png' };
  }
  if (normalized === 'image/jpeg' || normalized === 'image/jpg') {
    return { mimeType: 'image/jpeg', ext: 'jpg' };
  }
  if (normalized === 'image/webp') {
    return { mimeType: 'image/webp', ext: 'webp' };
  }

  const ext = path.extname(originalname).toLowerCase();
  if (ext === '.pdf') return { mimeType: 'application/pdf', ext: 'pdf' };
  if (ext === '.png') return { mimeType: 'image/png', ext: 'png' };
  if (ext === '.jpg' || ext === '.jpeg') return { mimeType: 'image/jpeg', ext: 'jpg' };
  if (ext === '.webp') return { mimeType: 'image/webp', ext: 'webp' };

  throw badRequest('Nepodporovaný formát výkresu');
}

async function getPdfPageSize(buffer: Buffer): Promise<{ width: number; height: number }> {
  const doc = await withTimeout(
    pdfToImg(buffer, { scale: 1 }),
    pdfParseTimeoutMs,
    'Zpracování PDF výkresu trvalo příliš dlouho',
  );
  try {
    const pageBuffer = await withTimeout(
      doc.getPage(1),
      pdfParseTimeoutMs,
      'Zpracování PDF výkresu trvalo příliš dlouho',
    );
    const meta = await sharp(pageBuffer).metadata();
    if (!meta.width || !meta.height) {
      throw badRequest('Nelze určit rozměry PDF výkresu');
    }
    return { width: meta.width, height: meta.height };
  } catch {
    throw badRequest('Soubor není platný PDF výkres');
  } finally {
    await doc.destroy();
  }
}

async function getImageDimensions(buffer: Buffer): Promise<{ width: number; height: number }> {
  try {
    const meta = await sharp(buffer, { failOn: 'error' }).metadata();
    if (!meta.width || !meta.height) {
      throw badRequest('Nelze určit rozměry výkresu');
    }
    return { width: meta.width, height: meta.height };
  } catch {
    throw badRequest('Soubor není platný obrázek výkresu');
  }
}

export async function getFloorDrawingBundle(floorId: string, role: UserRole, userId: string) {
  await assertFloorReadable(floorId, role, userId);

  const floor = await prisma.jobFloor.findFirst({
    where: { id: floorId, deletedAt: null },
    select: { jobId: true },
  });
  if (!floor) throw notFound('Patro nenalezeno');

  const drawing = await prisma.floorDrawing.findUnique({
    where: { floorId },
  });

  const markers = await prisma.sealMarker.findMany({
    where: {
      floorId,
      seal: { deletedAt: null },
    },
    include: {
      seal: {
        select: {
          id: true,
          sealNumber: true,
          status: true,
          reviewStatus: true,
          createdById: true,
          createdBy: { select: { id: true, displayName: true, username: true } },
        },
      },
    },
    orderBy: { seal: { sealNumber: 'asc' } },
  });

  return {
    drawing: drawing
      ? {
          id: drawing.id,
          floorId: drawing.floorId,
          filePath: drawing.filePath,
          mimeType: drawing.mimeType,
          width: drawing.width,
          height: drawing.height,
          updatedAt: drawing.updatedAt,
          fileUrl: `/api/jobs/${floor.jobId}/floors/${floorId}/drawing/file`,
        }
      : null,
    markers: markers.map((m) => ({
      id: m.id,
      sealId: m.sealId,
      floorId: m.floorId,
      x: m.x,
      y: m.y,
      sealNumber: m.seal.sealNumber,
      status: m.seal.status,
      reviewStatus: m.seal.reviewStatus,
      createdById: m.seal.createdById,
      createdByName:
        m.seal.createdBy.displayName ?? m.seal.createdBy.username ?? null,
      updatedAt: m.updatedAt,
    })),
  };
}

export async function getFloorDrawingFile(floorId: string, role: UserRole, userId: string) {
  await assertFloorReadable(floorId, role, userId);
  const drawing = await prisma.floorDrawing.findUnique({ where: { floorId } });
  if (!drawing) throw notFound('Výkres patra nenalezen');

  const storage = getObjectStorage();
  if (!(await storage.exists(drawing.filePath))) {
    throw notFound('Soubor výkresu nenalezen');
  }
  const body = await storage.get(drawing.filePath);
  return { body, mimeType: drawing.mimeType, filePath: drawing.filePath };
}

export async function uploadFloorDrawing(
  floorId: string,
  file: { buffer: Buffer; mimetype: string; originalname: string; size: number },
  userId: string,
  role: UserRole,
) {
  if (
    !hasPermission(role, 'floor.drawing.manage') &&
    !hasPermission(role, 'floor.manage') &&
    !hasPermission(role, 'job.manage')
  ) {
    throw forbidden('Nahrát výkres může pouze vedení nebo admin');
  }
  const floor = await assertFloorReadable(floorId, role, userId);
  await assertJobWritable(floor.jobId, role, userId);
  if (file.size > maxDrawingBytes) {
    throw badRequest(`Výkres nesmí být větší než ${maxDrawingBytes} B`);
  }

  const { mimeType, ext } = resolveDrawingMimeAndExt(file.mimetype, file.originalname);
  const output = file.buffer;

  const dimensions =
    mimeType === 'application/pdf'
      ? await getPdfPageSize(output)
      : await getImageDimensions(output);

  const storage = getObjectStorage();
  const filePath = sanitizeObjectKey(
    `drawing-${floorId.slice(0, 8)}-${Date.now()}.${ext}`,
  );

  const existing = await prisma.floorDrawing.findUnique({ where: { floorId } });

  // Nahraj nový soubor PŘED zápisem do DB. Starý soubor smažeme až po úspěšném
  // upsertu — kdyby DB selhala, zůstane funkční předchozí výkres a nezůstane
  // osiřelý nový soubor (rollback). Vzor dle photos.routes.ts.
  await storage.put(filePath, output, mimeType);

  let drawing;
  try {
    drawing = await prisma.floorDrawing.upsert({
      where: { floorId },
      create: {
        floorId,
        filePath,
        mimeType,
        width: dimensions.width,
        height: dimensions.height,
        fileSize: output.length,
        uploadedById: userId,
      },
      update: {
        filePath,
        mimeType,
        width: dimensions.width,
        height: dimensions.height,
        fileSize: output.length,
        uploadedById: userId,
      },
    });
  } catch (e) {
    try {
      await storage.delete(filePath);
    } catch {
      // best-effort rollback nově nahraného souboru
    }
    throw e;
  }

  if (existing && existing.filePath !== filePath) {
    try {
      await storage.delete(existing.filePath);
    } catch {
      // best effort — starý soubor už není referencovaný
    }
  }

  await logActivity(userId, 'floor_drawing_upload', 'job_floor', floorId, {
    drawingId: drawing.id,
  });

  return drawing;
}

export async function upsertSealMarker(
  floorId: string,
  sealId: string,
  x: number,
  y: number,
  userId: string,
  role: UserRole,
) {
  const nx = clamp01(x);
  const ny = clamp01(y);

  const seal = await assertSealReadable(sealId, role, userId);
  if (seal.floorId !== floorId) {
    throw badRequest('Ucpávka není na tomto patře');
  }

  if (role === UserRole.worker) {
    await assertSealEditable(sealId, role, userId);
  } else if (!hasPermission(role, 'seal.edit')) {
    throw forbidden('Nemáte oprávnění umístit značku');
  }

  const drawing = await prisma.floorDrawing.findUnique({ where: { floorId } });
  if (!drawing) throw badRequest('Patro nemá nahraný výkres');

  const marker = await prisma.$transaction(async (tx) => {
    const upserted = await tx.sealMarker.upsert({
      where: { sealId },
      create: {
        sealId,
        floorId,
        x: nx,
        y: ny,
        createdById: userId,
      },
      update: {
        floorId,
        x: nx,
        y: ny,
      },
    });
    await tx.seal.update({
      where: { id: sealId },
      data: { markerPlacementPending: false },
    });
    return upserted;
  });

  await logActivity(userId, 'seal_marker_upsert', 'seal', sealId, {
    floorId,
    x: nx,
    y: ny,
  });

  return marker;
}

export async function deleteSealMarker(sealId: string, userId: string, role: UserRole) {
  const seal = await assertSealReadable(sealId, role, userId);
  if (role === UserRole.worker) {
    await assertSealEditable(sealId, role, userId);
  } else if (!hasPermission(role, 'seal.edit')) {
    throw forbidden('Nemáte oprávnění smazat značku');
  }

  const existing = await prisma.sealMarker.findUnique({ where: { sealId } });
  if (!existing) throw notFound('Značka nenalezena');

  await prisma.sealMarker.delete({ where: { sealId } });
  await logActivity(userId, 'seal_marker_delete', 'seal', seal.id);
  return { ok: true };
}

export async function deleteFloorDrawing(
  floorId: string,
  userId: string,
  role: UserRole,
) {
  if (
    !hasPermission(role, 'floor.drawing.manage') &&
    !hasPermission(role, 'floor.manage') &&
    !hasPermission(role, 'job.manage')
  ) {
    throw forbidden('Smazat výkres může pouze vedení nebo admin');
  }
  const floor = await assertFloorReadable(floorId, role, userId);
  await assertJobWritable(floor.jobId, role, userId);

  const drawing = await prisma.floorDrawing.findUnique({ where: { floorId } });
  if (!drawing) throw notFound('Výkres patra nenalezen');

  const storage = getObjectStorage();
  try {
    await storage.delete(drawing.filePath);
  } catch {
    // best effort
  }

  await prisma.sealMarker.deleteMany({ where: { floorId } });
  await prisma.floorDrawing.delete({ where: { floorId } });
  await logActivity(userId, 'floor_drawing_delete', 'job_floor', floorId, {
    drawingId: drawing.id,
  });

  return { ok: true };
}

export async function getFloorPlacementStats(
  floorId: string,
  role: UserRole,
  userId: string,
) {
  await assertFloorReadable(floorId, role, userId);

  const total = await prisma.seal.count({
    where: { floorId, deletedAt: null },
  });
  const placed = await prisma.sealMarker.count({
    where: {
      floorId,
      seal: { deletedAt: null },
    },
  });

  return {
    total,
    placed,
    unplaced: Math.max(0, total - placed),
  };
}
