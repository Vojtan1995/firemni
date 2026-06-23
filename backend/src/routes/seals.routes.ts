import { Router } from "express";
import { z } from "zod";
import { SealStatus, UserRole, SealTrade } from "@prisma/client";
import { authMiddleware } from "../middleware/auth.middleware.js";
import { requirePermission } from "../lib/permissions.js";
import { prisma } from "../lib/prisma.js";
import { notFound } from "../lib/errors.js";
import {
  getSealHistory,
  logActivity,
  logChange,
} from "../services/audit.service.js";
import { touchJobParticipant } from "../services/job-participant.service.js";
import { priceSealEntries } from "../services/pricing.service.js";
import { paramId } from "../lib/params.js";
import {
  assertSealEditable,
  bulkChangeSealStatus,
  buildBulkSealsCsv,
  bulkMoveSeals,
  changeSealStatus,
  checkDuplicateSealNumber,
  restoreSeal,
  rethrowAsDuplicateSealNumber,
  reviewSeal,
  softDeleteSeal,
  statusAfterWorkerEdit,
} from "../services/seal.service.js";
import {
  entryCreateData,
  refineSealPatch,
  sealBodySchema,
  sealPatchObjectSchema,
} from "../lib/seal-schemas.js";
import {
  assertFloorBelongsToJob,
  assertFloorReadable,
  assertJobWritable,
  assertSealReadable,
} from "../services/authorization.service.js";
import {
  applySealNotePatchByRole,
  filterSealNotesForViewer,
  resolveSealNotesForCreate,
} from "../lib/seal-notes.js";
import { parseSealFilters } from "../lib/seal-list-filters.js";
import { listFloorSealsFiltered } from "../services/search.service.js";
import { getEntryWorksheetMembership } from "../services/worksheet.service.js";

const router = Router();
router.use(authMiddleware);

const showWorkerInList = (role: UserRole) =>
  role === UserRole.vedeni || role === UserRole.admin;

const canSeeSealOwner = (role: UserRole, viewerId: string, ownerId: string) =>
  role === UserRole.vedeni || role === UserRole.admin || viewerId === ownerId;

router.get(
  "/trash",
  requirePermission("admin.trash"),
  async (_req, res, next) => {
    try {
      const seals = await prisma.seal.findMany({
        where: { deletedAt: { not: null } },
        include: {
          job: { select: { projectNumber: true, name: true } },
          floor: { select: { name: true } },
        },
        orderBy: { deletedAt: "desc" },
        take: 200,
      });

      const deleterIds = [
        ...new Set(
          seals.map((s) => s.deletedById).filter((id): id is string => !!id),
        ),
      ];
      const deleters =
        deleterIds.length > 0
          ? await prisma.user.findMany({
              where: { id: { in: deleterIds } },
              select: { id: true, displayName: true, username: true },
            })
          : [];
      const deleterMap = new Map(deleters.map((u) => [u.id, u]));

      res.json(
        seals.map((s) => {
          const deleter = s.deletedById
            ? deleterMap.get(s.deletedById)
            : undefined;
          return {
            entityType: "seal",
            id: s.id,
            sealNumber: s.sealNumber,
            status: s.status,
            stavba: s.job.projectNumber,
            nazevStavby: s.job.name,
            patro: s.floor.name,
            deletedAt: s.deletedAt,
            deletedByName: deleter?.displayName ?? deleter?.username ?? null,
            deleteReason: s.deleteReason,
          };
        }),
      );
    } catch (e) {
      next(e);
    }
  },
);

router.get("/floors/:floorId/seals", async (req, res, next) => {
  try {
    const role = req.user!.role;
    const userId = req.user!.id;
    const floorId = paramId(req.params.floorId);
    await assertFloorReadable(floorId, role, userId);
    const showWorker = showWorkerInList(role);
    const filters = parseSealFilters(
      req.query.filters as string | string[] | undefined,
    );
    const tradeRaw = req.query.trade as string | undefined;
    const trade =
      tradeRaw && (Object.values(SealTrade) as string[]).includes(tradeRaw)
        ? (tradeRaw as SealTrade)
        : undefined;
    const seals = await listFloorSealsFiltered({
      floorId,
      role,
      userId,
      showWorker,
      filters,
      trade,
    });

    res.json(
      seals.map((s) => ({
        id: s.id,
        sealNumber: s.sealNumber,
        trade: s.trade,
        status: s.status,
        version: s.version,
        updatedAt: s.updatedAt,
        photoCount: s._count.photos,
        hasPublicNote: role !== UserRole.worker && !!s.note?.trim(),
        hasInternalNote: !!s.internalNote?.trim(),
        reviewStatus: s.reviewStatus,
        markerPlacementPending: s.markerPlacementPending,
        worker: showWorker && "createdBy" in s ? s.createdBy : undefined,
        worksheetStatus: canSeeSealOwner(role, userId, s.createdById)
          ? s.worksheetStatus
          : null,
      })),
    );
  } catch (e) {
    next(e);
  }
});

router.post(
  "/bulk-status",
  requirePermission("seal.status"),
  async (req, res, next) => {
    try {
      const body = z
        .object({
          ids: z.array(z.string().uuid()).min(1),
          status: z.nativeEnum(SealStatus),
          comment: z.string().max(2000).optional(),
        })
        .parse(req.body);
      const { succeeded, failed } = await bulkChangeSealStatus(
        body.ids,
        body.status,
        req.user!.id,
        req.user!.role,
        body.comment,
      );
      res.json({
        updated: succeeded.length,
        failed: failed.length,
        seals: succeeded,
        errors: failed,
      });
    } catch (e) {
      next(e);
    }
  },
);

router.post(
  "/bulk-move",
  requirePermission("seal.edit"),
  async (req, res, next) => {
    try {
      const body = z
        .object({
          ids: z.array(z.string().uuid()).min(1),
          floorId: z.string().uuid(),
        })
        .parse(req.body);
      const { succeeded, failed, targetFloorName } = await bulkMoveSeals(
        body.ids,
        body.floorId,
        req.user!.id,
        req.user!.role,
      );
      res.json({
        moved: succeeded.length,
        failed: failed.length,
        targetFloorName,
        seals: succeeded,
        errors: failed,
      });
    } catch (e) {
      next(e);
    }
  },
);

router.post(
  "/bulk-export/csv",
  requirePermission("reports.export"),
  async (req, res, next) => {
    try {
      const body = z
        .object({
          ids: z.array(z.string().uuid()).min(1),
        })
        .parse(req.body);
      const csv = await buildBulkSealsCsv(
        body.ids,
        req.user!.id,
        req.user!.role,
      );
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader(
        "Content-Disposition",
        'attachment; filename="vybrane-ucpavky.csv"',
      );
      res.send(csv);
    } catch (e) {
      next(e);
    }
  },
);

router.get(
  "/:id/history",
  requirePermission("seal.history"),
  async (req, res, next) => {
    try {
      const sealId = paramId(req.params.id);
      await assertSealReadable(sealId, req.user!.role, req.user!.id);
      const history = await getSealHistory(sealId, req.user!.role);
      res.json(history);
    } catch (e) {
      next(e);
    }
  },
);

router.get("/:id", async (req, res, next) => {
  try {
    const sealId = paramId(req.params.id);
    await assertSealReadable(sealId, req.user!.role, req.user!.id);
    const seal = await prisma.seal.findFirst({
      where: { id: sealId, deletedAt: null },
      include: {
        createdBy: { select: { id: true, displayName: true, username: true } },
        updatedBy: { select: { id: true, displayName: true, username: true } },
        entries: {
          where: { deletedAt: null },
          include: { materials: { orderBy: { sortOrder: "asc" } } },
          orderBy: { sortOrder: "asc" },
        },
        photos: {
          orderBy: { createdAt: "asc" },
          include: { uploadedBy: { select: { id: true, displayName: true } } },
        },
        marker: {
          select: {
            id: true,
            floorId: true,
            x: true,
            y: true,
            updatedAt: true,
          },
        },
      },
    });
    if (!seal) throw notFound("Ucpávka nenalezena");

    const showPrivateSealContext = canSeeSealOwner(
      req.user!.role,
      req.user!.id,
      seal.createdById,
    );
    const membership = showPrivateSealContext
      ? await getEntryWorksheetMembership(seal.entries.map((e) => e.id))
      : new Map();
    const sealWithMembership = {
      ...seal,
      createdBy: showPrivateSealContext ? seal.createdBy : undefined,
      entries: seal.entries.map((e) => {
        const m = membership.get(e.id);
        return {
          ...e,
          worksheet: m
            ? {
                worksheetId: m.worksheetId,
                status: m.status,
                jobProjectNumber: m.jobProjectNumber,
              }
            : null,
        };
      }),
    };
    res.json(filterSealNotesForViewer(req.user!.role, sealWithMembership));
  } catch (e) {
    next(e);
  }
});

router.post("/", requirePermission("seal.create"), async (req, res, next) => {
  try {
    const body = sealBodySchema.parse(req.body);
    await assertJobWritable(body.jobId, req.user!.role, req.user!.id);
    await assertFloorBelongsToJob(body.floorId, body.jobId);
    await checkDuplicateSealNumber(body.jobId, body.floorId, body.sealNumber);

    const notes = resolveSealNotesForCreate(req.user!.role, {
      note: body.note,
      internalNote: body.internalNote,
    });

    const priced = await prisma
      .$transaction(async (tx) => {
        const seal = await tx.seal.create({
          data: {
            jobId: body.jobId,
            floorId: body.floorId,
            sealNumber: body.sealNumber,
            trade: body.trade,
            system: body.system,
            construction: body.construction,
            location: body.location,
            fireRating: body.fireRating,
            note: notes.note,
            internalNote: notes.internalNote,
            openingLengthMm: body.openingLengthMm ?? null,
            openingWidthMm: body.openingWidthMm ?? null,
            markerPlacementPending: body.markerPlacementPending ?? false,
            status: SealStatus.draft,
            createdById: req.user!.id,
            updatedById: req.user!.id,
            entries: {
              create: body.entries.map((e, i) => entryCreateData(e, i)),
            },
          },
        });
        await priceSealEntries(seal.id, req.user!.id, tx);
        return tx.seal.findFirst({
          where: { id: seal.id },
          include: {
            entries: {
              where: { deletedAt: null },
              include: { materials: true },
            },
            photos: true,
            createdBy: { select: { id: true, displayName: true } },
            updatedBy: { select: { id: true, displayName: true } },
          },
        });
      })
      .catch(rethrowAsDuplicateSealNumber);

    await logActivity(req.user!.id, "create", "seal", priced!.id);
    await touchJobParticipant(body.jobId, req.user!.id, "worker");
    res.status(201).json(priced);
  } catch (e) {
    next(e);
  }
});

router.patch("/:id", requirePermission("seal.edit"), async (req, res, next) => {
  try {
    const body = sealPatchObjectSchema
      .extend({
        baseVersion: z.number().int(),
        overrideReason: z.string().max(2000).optional(),
      })
      .superRefine(refineSealPatch)
      .parse(req.body);

    const existing = await assertSealEditable(
      paramId(req.params.id),
      req.user!.role,
      req.user!.id,
      {
        overrideLocked: true,
        overrideReason: body.overrideReason,
        entriesChanged: !!body.entries,
      },
    );

    if (
      body.baseVersion !== undefined &&
      body.baseVersion !== existing.version
    ) {
      const { conflict: c } = await import("../lib/errors.js");
      throw c("Entita byla mezitím změněna jiným uživatelem");
    }

    if (body.sealNumber && body.sealNumber !== existing.sealNumber) {
      await checkDuplicateSealNumber(
        existing.jobId,
        existing.floorId,
        body.sealNumber,
        existing.id,
      );
    }

    const updateData: Record<string, unknown> = {
      version: { increment: 1 },
      updatedById: req.user!.id,
    };
    const nextStatus = statusAfterWorkerEdit(existing.status, req.user!.role);
    if (nextStatus !== existing.status) {
      updateData.status = nextStatus;
      await logChange(
        req.user!.id,
        "seal",
        existing.id,
        "status",
        existing.status,
        nextStatus,
      );
    }

    const resolvedNotes = applySealNotePatchByRole(
      req.user!.role,
      { note: existing.note, internalNote: existing.internalNote },
      { note: body.note, internalNote: body.internalNote },
    );
    if (body.note !== undefined && resolvedNotes.note !== existing.note) {
      await logChange(
        req.user!.id,
        "seal",
        existing.id,
        "note",
        String(existing.note ?? ""),
        String(resolvedNotes.note ?? ""),
      );
      updateData.note = resolvedNotes.note;
    }
    if (
      body.internalNote !== undefined &&
      resolvedNotes.internalNote !== existing.internalNote
    ) {
      await logChange(
        req.user!.id,
        "seal",
        existing.id,
        "internalNote",
        String(existing.internalNote ?? ""),
        String(resolvedNotes.internalNote ?? ""),
      );
      updateData.internalNote = resolvedNotes.internalNote;
    }

    const fields = [
      "sealNumber",
      "trade",
      "system",
      "construction",
      "location",
      "fireRating",
      "openingLengthMm",
      "openingWidthMm",
      "markerPlacementPending",
    ] as const;
    for (const f of fields) {
      if (body[f] !== undefined) {
        if (String(existing[f]) !== String(body[f])) {
          await logChange(
            req.user!.id,
            "seal",
            existing.id,
            f,
            String(existing[f] ?? ""),
            String(body[f]),
          );
        }
        updateData[f] = body[f];
      }
    }

    let seal;
    if (body.entries) {
      await logChange(
        req.user!.id,
        "seal",
        existing.id,
        "entries",
        "updated",
        "updated",
      );
      seal = await prisma
        .$transaction(async (tx) => {
          await tx.sealEntry.updateMany({
            where: { sealId: existing.id },
            data: { deletedAt: new Date() },
          });
          for (let i = 0; i < body.entries!.length; i++) {
            const e = body.entries![i];
            const entry = await tx.sealEntry.create({
              data: {
                sealId: existing.id,
                entryType: e.entryType,
                dimension: e.dimension,
                quantity: e.quantity,
                insulation: e.insulation,
                itemLengthMm: e.itemLengthMm ?? null,
                itemWidthMm: e.itemWidthMm ?? null,
                steelInsulated: e.steelInsulated ?? null,
                electroInstallationType: e.electroInstallationType ?? null,
                sortOrder: i,
              },
            });
            await tx.sealEntryMaterial.createMany({
              data: e.materials.map((m, j) => ({
                entryId: entry.id,
                material: m,
                sortOrder: j,
              })),
            });
          }
          await tx.seal.update({
            where: { id: existing.id },
            data: updateData,
          });
          await priceSealEntries(existing.id, req.user!.id, tx);
          return tx.seal.findFirst({
            where: { id: existing.id },
            include: {
              entries: {
                where: { deletedAt: null },
                include: { materials: true },
              },
              photos: true,
              createdBy: { select: { id: true, displayName: true } },
              updatedBy: { select: { id: true, displayName: true } },
            },
          });
        })
        .catch(rethrowAsDuplicateSealNumber);
    } else {
      seal = await prisma.seal
        .update({
          where: { id: existing.id },
          data: updateData,
          include: {
            entries: {
              where: { deletedAt: null },
              include: { materials: true },
            },
            photos: true,
            createdBy: { select: { id: true, displayName: true } },
            updatedBy: { select: { id: true, displayName: true } },
          },
        })
        .catch(rethrowAsDuplicateSealNumber);
    }

    if (!seal) throw notFound("Ucpávka nenalezena");

    await logActivity(req.user!.id, "update", "seal", seal.id);
    await touchJobParticipant(existing.jobId, req.user!.id, "worker");
    res.json(seal);
  } catch (e) {
    next(e);
  }
});

router.patch(
  "/:id/status",
  requirePermission("seal.status"),
  async (req, res, next) => {
    try {
      const body = z
        .object({
          status: z.nativeEnum(SealStatus),
          comment: z.string().max(2000).optional(),
        })
        .parse(req.body);
      const seal = await changeSealStatus(
        paramId(req.params.id),
        body.status,
        req.user!.id,
        req.user!.role,
        body.comment,
      );
      res.json(seal);
    } catch (e) {
      next(e);
    }
  },
);

router.patch(
  "/:id/review",
  requirePermission("seal.status"),
  async (req, res, next) => {
    try {
      const body = z
        .object({
          action: z.enum(["approved", "returned"]),
          comment: z.string().max(2000).optional(),
        })
        .parse(req.body);
      const seal = await reviewSeal(
        paramId(req.params.id),
        body.action,
        req.user!.id,
        req.user!.role,
        body.comment,
      );
      res.json(seal);
    } catch (e) {
      next(e);
    }
  },
);

router.delete(
  "/:id",
  requirePermission("seal.delete"),
  async (req, res, next) => {
    try {
      const reason =
        typeof req.body?.reason === "string"
          ? req.body.reason.slice(0, 2000)
          : undefined;
      const seal = await softDeleteSeal(
        paramId(req.params.id),
        req.user!.id,
        req.user!.role,
        reason,
      );
      res.json(seal);
    } catch (e) {
      next(e);
    }
  },
);

router.patch(
  "/:id/restore",
  requirePermission("seal.restore"),
  async (req, res, next) => {
    try {
      const seal = await restoreSeal(
        paramId(req.params.id),
        req.user!.id,
        req.user!.role,
      );
      res.json(seal);
    } catch (e) {
      next(e);
    }
  },
);

export default router;
