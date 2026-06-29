import sharp from "sharp";
import { pdf as pdfToImg } from "pdf-to-img";
import type { Response } from "express";
import { SealStatus, UserRole } from "@prisma/client";
import { prisma } from "../lib/prisma.js";
import { badRequest, notFound } from "../lib/errors.js";
import {
  createCzechPdfDocument,
  writePdfTextLine,
} from "../lib/pdf-pagination.js";
import { assertFloorReadable } from "./authorization.service.js";
import { getFloorDrawingFile } from "./floor-drawing.service.js";
const STATUS_LABELS: Record<SealStatus, string> = {
  [SealStatus.draft]: "Rozpracováno",
  [SealStatus.checked]: "Zkontrolováno",
  [SealStatus.invoiced]: "Fakturováno",
};

const STATUS_COLORS: Record<SealStatus, string> = {
  [SealStatus.draft]: "#DC2626",
  [SealStatus.checked]: "#22C55E",
  [SealStatus.invoiced]: "#666666",
};

const exportImageMaxDim = 2200;

export type FloorDrawingExportFilters = {
  status?: SealStatus;
  reviewStatus?: "returned";
  workerId?: string;
  sealIds?: string[];
  from?: string;
  to?: string;
};

function markerColor(status: SealStatus, reviewStatus: string | null) {
  if (reviewStatus === "returned") return "#F59E0B";
  return STATUS_COLORS[status] ?? "#3B82F6";
}

function filterLabel(filters: FloorDrawingExportFilters) {
  const parts: string[] = [];
  if (filters.reviewStatus === "returned") parts.push("Stav: Vráceno k opravě");
  else if (filters.status) parts.push(`Stav: ${STATUS_LABELS[filters.status]}`);
  if (filters.workerId) parts.push(`Montér: ${filters.workerId}`);
  if (filters.sealIds?.length)
    parts.push(`Vybrané ucpávky: ${filters.sealIds.length}`);
  if (filters.from || filters.to)
    parts.push(`Období: ${filters.from ?? "—"} – ${filters.to ?? "—"}`);
  return parts.length ? parts.join(", ") : "Všechny ucpávky";
}

export async function exportFloorDrawingPdf(
  jobId: string,
  floorId: string,
  role: UserRole,
  userId: string,
  res: Response,
  filters: FloorDrawingExportFilters,
) {
  await assertFloorReadable(floorId, role, userId);

  const job = await prisma.job.findFirst({
    where: { id: jobId, deletedAt: null },
  });
  if (!job) throw notFound("Stavba nenalezena");

  const floor = await prisma.jobFloor.findFirst({
    where: { id: floorId, jobId, deletedAt: null },
  });
  if (!floor) throw notFound("Patro nenalezeno");

  const drawing = await prisma.floorDrawing.findUnique({ where: { floorId } });
  if (!drawing) throw badRequest("Patro nemá nahraný výkres");

  const sealWhere: Record<string, unknown> = {
    deletedAt: null,
  };
  if (filters.reviewStatus === "returned") {
    sealWhere.reviewStatus = "returned";
  } else if (filters.status) {
    sealWhere.status = filters.status;
    if (filters.status === SealStatus.draft) {
      sealWhere.reviewStatus = { not: "returned" };
    }
  }
  if (filters.workerId) sealWhere.createdById = filters.workerId;
  if (filters.sealIds?.length) sealWhere.id = { in: filters.sealIds };
  if (filters.from || filters.to) {
    sealWhere.updatedAt = {
      ...(filters.from ? { gte: new Date(filters.from) } : {}),
      ...(filters.to ? { lte: new Date(`${filters.to}T23:59:59.999Z`) } : {}),
    };
  }

  const markers = await prisma.sealMarker.findMany({
    where: { floorId, seal: sealWhere },
    include: {
      seal: {
        select: {
          id: true,
          sealNumber: true,
          status: true,
          reviewStatus: true,
          system: true,
          fireRating: true,
          createdBy: { select: { displayName: true } },
        },
      },
    },
    orderBy: { seal: { sealNumber: "asc" } },
  });

  if (filters.status === SealStatus.draft) {
    // include returned in draft filter optionally - skip
  }

  let filtered = markers;
  if (filters.status === undefined && filters.sealIds?.length) {
    filtered = markers;
  }

  const file = await getFloorDrawingFile(floorId, role, userId);
  let image: Buffer;
  if (file.mimeType === "application/pdf") {
    const doc = await pdfToImg(file.body, { scale: 4 });
    try {
      const page = await doc.getPage(1);
      image = await sharp(page)
        .resize(exportImageMaxDim, exportImageMaxDim, {
          fit: "inside",
          withoutEnlargement: true,
        })
        .png({ compressionLevel: 9 })
        .toBuffer();
    } finally {
      await doc.destroy();
    }
  } else {
    image = await sharp(file.body)
      .resize(exportImageMaxDim, exportImageMaxDim, {
        fit: "inside",
        withoutEnlargement: true,
      })
      .png({ compressionLevel: 9 })
      .toBuffer();
  }
  const meta = await sharp(image).metadata();
  const imgPixelW = meta.width ?? 400;
  const imgPixelH = meta.height ?? 300;

  const filename = `vykres-${job.projectNumber}-${floor.name.replace(/\s+/g, "-")}.pdf`;
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);

  const doc = createCzechPdfDocument({ margin: 40, size: "A4" });
  doc.pipe(res);

  const exportDate = new Date().toISOString().split("T")[0];
  doc.fontSize(16).text("Export výkresu patra", { underline: true });
  doc.moveDown(0.4);
  doc.fontSize(10);
  doc.text(`Zakázka: ${job.projectNumber} – ${job.name}`);
  doc.text(`Patro: ${floor.name}`);
  doc.text(`Datum exportu: ${exportDate}`);
  doc.text(`Filtr: ${filterLabel(filters)}`);
  doc.moveDown();

  const x0 = doc.x;
  const y0 = doc.y;
  const maxDisplayW =
    doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const maxDisplayH = 470;
  const displayScale = Math.min(
    maxDisplayW / imgPixelW,
    maxDisplayH / imgPixelH,
  );
  const imgW = imgPixelW * displayScale;
  const imgH = imgPixelH * displayScale;
  doc.image(image, x0, y0, { width: imgW, height: imgH });

  for (const m of filtered) {
    const cx = x0 + m.x * imgW;
    const cy = y0 + m.y * imgH;
    const color = markerColor(m.seal.status, m.seal.reviewStatus);
    const hasOffset =
      (m.labelOffsetX != null && m.labelOffsetX !== 0) ||
      (m.labelOffsetY != null && m.labelOffsetY !== 0);

    if (!hasOffset) {
      const r = 6;
      doc.circle(cx, cy, r).fill(color);
      doc
        .fillColor("#FFFFFF")
        .fontSize(6)
        .text(m.seal.sealNumber, cx - r, cy - 3, {
          width: r * 2,
          align: "center",
        });
      doc.fillColor("#000000");
      continue;
    }

    const lx = cx + (m.labelOffsetX ?? 0) * imgW;
    const ly = cy + (m.labelOffsetY ?? 0) * imgH;
    const dotR = 2;
    doc
      .moveTo(cx, cy)
      .lineTo(lx, ly)
      .strokeColor("#555555")
      .lineWidth(0.5)
      .stroke();
    doc.circle(cx, cy, dotR).fill(color);

    const r = 6;
    doc.circle(lx, ly, r).fill(color);
    doc
      .fillColor("#FFFFFF")
      .fontSize(6)
      .text(m.seal.sealNumber, lx - r, ly - 3, {
        width: r * 2,
        align: "center",
      });
    doc.fillColor("#000000");
  }

  doc.y = y0 + imgH + 16;
  doc.fontSize(11).text("Legenda barev", { underline: true });
  doc.fontSize(9);
  doc
    .fillColor(STATUS_COLORS[SealStatus.draft])
    .text("● Rozpracováno", { continued: false });
  doc
    .fillColor(STATUS_COLORS[SealStatus.checked])
    .text("● Zkontrolováno", { continued: false });
  doc
    .fillColor(STATUS_COLORS[SealStatus.invoiced])
    .text("● Fakturováno", { continued: false });
  doc.fillColor("#F59E0B").text("● Vráceno k opravě");
  doc.fillColor("#000000");
  doc.moveDown();

  doc.fontSize(11).text("Seznam exportovaných ucpávek", { underline: true });
  doc.fontSize(8);
  for (const m of filtered) {
    const statusLabel =
      m.seal.reviewStatus === "returned"
        ? "Vráceno k opravě"
        : STATUS_LABELS[m.seal.status];
    writePdfTextLine(
      doc,
      `${m.seal.sealNumber} - ${m.seal.system} - ${m.seal.fireRating} - ${m.seal.createdBy.displayName} - ${statusLabel}`,
    );
  }

  doc.end();
}
