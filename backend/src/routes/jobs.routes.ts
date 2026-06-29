import { Router } from "express";
import { z } from "zod";
import { JobStatus, UserRole } from "@prisma/client";
import { authMiddleware, requireRole } from "../middleware/auth.middleware.js";
import { prisma } from "../lib/prisma.js";
import { notFound, badRequest, conflict } from "../lib/errors.js";
import { logActivity } from "../services/audit.service.js";
import { MANAGEMENT_ROLES } from "../services/seal.service.js";
import { paramId } from "../lib/params.js";
import { requirePermission } from "../lib/permissions.js";
import * as jobParticipantService from "../services/job-participant.service.js";
import { assertJobReadable } from "../services/authorization.service.js";
import { jobStatusPatch, parseJobStatusQuery } from "../lib/job-status.js";
import { exportJobCsv, exportJobPdf } from "../services/job-export.service.js";
import { jobNumberRateLimiter } from "../middleware/security.middleware.js";

const router = Router();
router.use(authMiddleware);

const projectNumberSchema = z
  .string()
  .regex(/^\d{8}$/, "Číslo stavby musí mít 8 číslic");

router.get("/my", async (req, res, next) => {
  try {
    const role = req.user!.role;
    const jobs =
      role === UserRole.worker
        ? await jobParticipantService.listMyJobs(req.user!.id)
        : await jobParticipantService.listAllActiveJobs();
    res.json(jobs);
  } catch (e) {
    next(e);
  }
});

router.get(
  "/:jobId/participants",
  requirePermission("job.manage"),
  async (req, res, next) => {
    try {
      const jobId = paramId(req.params.jobId);
      const job = await prisma.job.findFirst({
        where: { id: jobId, deletedAt: null },
      });
      if (!job) throw notFound("Stavba nenalezena");
      const participants =
        await jobParticipantService.listJobParticipants(jobId);
      res.json(participants);
    } catch (e) {
      next(e);
    }
  },
);

router.post(
  "/:jobId/participants",
  requirePermission("job.manage"),
  async (req, res, next) => {
    try {
      const jobId = paramId(req.params.jobId);
      const body = z
        .object({
          userId: z.string().uuid(),
          roleOnJob: z.string().min(1).default("assigned"),
        })
        .parse(req.body);
      const job = await prisma.job.findFirst({
        where: { id: jobId, deletedAt: null },
      });
      if (!job) throw notFound("Stavba nenalezena");
      await jobParticipantService.touchJobParticipant(
        jobId,
        body.userId,
        body.roleOnJob,
        req.user!.id,
      );
      res.status(201).json({ ok: true });
    } catch (e) {
      next(e);
    }
  },
);

router.delete(
  "/:jobId/participants/:userId",
  requirePermission("job.manage"),
  async (req, res, next) => {
    try {
      await prisma.jobParticipant.deleteMany({
        where: {
          jobId: paramId(req.params.jobId),
          userId: paramId(req.params.userId),
        },
      });
      res.json({ ok: true });
    } catch (e) {
      next(e);
    }
  },
);

router.get(
  "/",
  requireRole(UserRole.vedeni, UserRole.admin),
  async (req, res, next) => {
    try {
      const status =
        parseJobStatusQuery(
          req.query.status as string | undefined,
          req.query.archived as string | undefined,
        ) ?? JobStatus.active;
      const withoutActivity = req.query.filter === "without_activity";
      const jobs = await prisma.job.findMany({
        where: {
          deletedAt: null,
          status,
          ...(withoutActivity ? { seals: { none: { deletedAt: null } } } : {}),
        },
        include: {
          floors: { where: { deletedAt: null }, orderBy: { sortOrder: "asc" } },
        },
        orderBy: { createdAt: "desc" },
      });
      res.json(jobs);
    } catch (e) {
      next(e);
    }
  },
);

router.get(
  "/by-number/:projectNumber",
  jobNumberRateLimiter,
  async (req, res, next) => {
    try {
      const num = projectNumberSchema.parse(req.params.projectNumber);
      const job = await prisma.job.findFirst({
        where: { projectNumber: num, deletedAt: null },
        include: {
          floors: { where: { deletedAt: null }, orderBy: { sortOrder: "asc" } },
        },
      });
      if (!job) throw notFound("Stavba s tímto číslem neexistuje");
      if (req.user!.role === UserRole.worker) {
        await jobParticipantService.joinJobByNumber(job.id, req.user!.id);
      } else {
        await assertJobReadable(job.id, req.user!.role, req.user!.id);
      }
      res.json(job);
    } catch (e) {
      next(e);
    }
  },
);

const createJobSchema = z.object({
  projectNumber: projectNumberSchema,
  name: z.string().min(1).max(200),
  address: z.string().max(200).optional(),
  note: z.string().max(2000).optional(),
});

router.post("/", requireRole(...MANAGEMENT_ROLES), async (req, res, next) => {
  try {
    const body = createJobSchema.parse(req.body);
    const existing = await prisma.job.findUnique({
      where: { projectNumber: body.projectNumber },
    });
    if (existing) throw badRequest("Stavba s tímto číslem již existuje");

    const job = await prisma.job.create({
      data: { ...body, createdById: req.user!.id },
    });
    await logActivity(req.user!.id, "create", "job", job.id, {
      projectNumber: job.projectNumber,
      jobName: job.name,
    });
    res.status(201).json(job);
  } catch (e) {
    next(e);
  }
});

const updateJobSchema = z.object({
  name: z.string().min(1).max(200).optional(),
  address: z.string().max(200).optional().nullable(),
  note: z.string().max(2000).optional().nullable(),
});

const deleteReasonSchema = z.object({
  deleteReason: z.string().max(2000).optional(),
});

async function getActiveJob(id: string) {
  const job = await prisma.job.findFirst({ where: { id, deletedAt: null } });
  if (!job) throw notFound("Stavba nenalezena");
  return job;
}

router.patch(
  "/:id/archive",
  requireRole(...MANAGEMENT_ROLES),
  async (req, res, next) => {
    try {
      const id = paramId(req.params.id);
      const current = await getActiveJob(id);
      const job = await prisma.job.update({
        where: { id },
        data: jobStatusPatch(JobStatus.archived),
      });
      await logActivity(req.user!.id, "archive", "job", job.id, {
        projectNumber: current.projectNumber,
        jobName: current.name,
      });
      res.json(job);
    } catch (e) {
      next(e);
    }
  },
);

router.patch(
  "/:id/complete",
  requireRole(...MANAGEMENT_ROLES),
  async (req, res, next) => {
    try {
      const id = paramId(req.params.id);
      const current = await getActiveJob(id);
      const job = await prisma.job.update({
        where: { id },
        data: jobStatusPatch(JobStatus.completed),
      });
      await logActivity(req.user!.id, "complete", "job", job.id, {
        projectNumber: current.projectNumber,
        jobName: current.name,
      });
      res.json(job);
    } catch (e) {
      next(e);
    }
  },
);

router.patch(
  "/:id/unarchive",
  requireRole(...MANAGEMENT_ROLES),
  async (req, res, next) => {
    try {
      const id = paramId(req.params.id);
      const current = await getActiveJob(id);
      const job = await prisma.job.update({
        where: { id },
        data: jobStatusPatch(JobStatus.active),
      });
      await logActivity(req.user!.id, "unarchive", "job", job.id, {
        projectNumber: current.projectNumber,
        jobName: current.name,
      });
      res.json(job);
    } catch (e) {
      next(e);
    }
  },
);

router.patch(
  "/:id/activate",
  requireRole(...MANAGEMENT_ROLES),
  async (req, res, next) => {
    try {
      const id = paramId(req.params.id);
      const current = await getActiveJob(id);
      const job = await prisma.job.update({
        where: { id },
        data: jobStatusPatch(JobStatus.active),
      });
      await logActivity(req.user!.id, "activate", "job", job.id, {
        projectNumber: current.projectNumber,
        jobName: current.name,
      });
      res.json(job);
    } catch (e) {
      next(e);
    }
  },
);

router.get(
  "/:id/export/csv",
  requirePermission("reports.export"),
  async (req, res, next) => {
    try {
      const jobId = paramId(req.params.id);
      const { csv, filename } = await exportJobCsv(
        jobId,
        req.user!.role,
        req.user!.id,
      );
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${filename}"`,
      );
      res.send(csv);
    } catch (e) {
      next(e);
    }
  },
);

router.get(
  "/:id/export/pdf",
  requirePermission("reports.export"),
  async (req, res, next) => {
    try {
      const jobId = paramId(req.params.id);
      await exportJobPdf(jobId, req.user!.role, req.user!.id, res);
    } catch (e) {
      next(e);
    }
  },
);

router.get(
  "/:id/activity",
  requirePermission("job.manage"),
  async (req, res, next) => {
    try {
      const jobId = paramId(req.params.id);
      const job = await prisma.job.findFirst({
        where: { id: jobId, deletedAt: null },
      });
      if (!job) throw notFound("Stavba nenalezena");

      const sealIds = (
        await prisma.seal.findMany({
          where: { jobId, deletedAt: null },
          select: { id: true },
        })
      ).map((s) => s.id);

      const [activities, changes, seals] = await Promise.all([
        prisma.activityLog.findMany({
          where: {
            OR: [
              { entityType: "job", entityId: jobId },
              { entityType: "seal", entityId: { in: sealIds } },
            ],
          },
          include: { user: { select: { displayName: true, username: true } } },
          orderBy: { createdAt: "desc" },
          take: 100,
        }),
        prisma.changeLog.findMany({
          where: { entityType: "seal", entityId: { in: sealIds } },
          include: { user: { select: { displayName: true } } },
          orderBy: { createdAt: "desc" },
          take: 100,
        }),
        prisma.seal.groupBy({
          by: ["status"],
          where: { jobId, deletedAt: null },
          _count: { id: true },
        }),
      ]);

      res.json({ activities, changes, sealStatusBreakdown: seals });
    } catch (e) {
      next(e);
    }
  },
);

router.patch(
  "/:id",
  requireRole(...MANAGEMENT_ROLES),
  async (req, res, next) => {
    try {
      const id = paramId(req.params.id);
      const current = await getActiveJob(id);
      const body = updateJobSchema.parse(req.body);
      if (Object.keys(body).length === 0)
        throw badRequest("Žádná pole k úpravě");

      const job = await prisma.job.update({
        where: { id },
        data: {
          ...(body.name !== undefined ? { name: body.name } : {}),
          ...(body.address !== undefined ? { address: body.address } : {}),
          ...(body.note !== undefined ? { note: body.note } : {}),
        },
      });
      await logActivity(req.user!.id, "update", "job", job.id, {
        projectNumber: job.projectNumber,
        jobName: job.name,
        previousProjectNumber: current.projectNumber,
        previousJobName: current.name,
      });
      res.json(job);
    } catch (e) {
      next(e);
    }
  },
);

router.delete(
  "/:id",
  requireRole(...MANAGEMENT_ROLES),
  async (req, res, next) => {
    try {
      const id = paramId(req.params.id);
      const current = await getActiveJob(id);
      const { deleteReason } = deleteReasonSchema.parse(req.body ?? {});

      const activeSeals = await prisma.seal.count({
        where: { jobId: id, deletedAt: null },
      });
      if (activeSeals > 0) {
        throw conflict("Stavbu nelze smazat – obsahuje aktivní ucpávky");
      }

      const job = await prisma.job.update({
        where: { id },
        data: {
          deletedAt: new Date(),
          deletedById: req.user!.id,
          deleteReason: deleteReason ?? null,
        },
      });
      await logActivity(req.user!.id, "soft_delete", "job", job.id, {
        projectNumber: current.projectNumber,
        jobName: current.name,
      });
      res.json({ ok: true, id: job.id });
    } catch (e) {
      next(e);
    }
  },
);

export default router;
