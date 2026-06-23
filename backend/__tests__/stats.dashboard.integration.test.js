import { describe, it, expect, beforeAll, afterAll } from "@jest/globals";
import request from "supertest";
import { createApp } from "../dist/app.js";
import { prisma } from "../dist/lib/prisma.js";

const SEAL_PREFIX = `8850${Date.now().toString().slice(-5)}`;

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: "elektrikari",
    system: "Stats",
    construction: "Stěna",
    location: "Chodba",
    fireRating: "EI 60",
    entries: [
      {
        entryType: "EL.V.",
        electroInstallationType: "Svazek",
        dimension: "Ø20",
        quantity: 1,
        insulation: "žádná",
        materials: ["Pěna"],
      },
    ],
  };
}

describe("Management dashboard stats (task 5.2)", () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floor1Id;
  let sealId;
  let workerId;
  let extraJobId;
  let targetWorksheetId;
  let extraWorksheetId;
  let completedJobId;
  let completedSealId;
  let completedWorksheetId;

  async function login(username) {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username, pin: "123456" });
    expect(res.status).toBe(200);
    return res.body;
  }

  beforeAll(async () => {
    const worker = await login("worker1");
    workerToken = worker.token;
    workerId = worker.user.id;
    managementToken = (await login("vedeni")).token;

    const jobRes = await request(app)
      .get("/api/jobs/by-number/12345678")
      .set("Authorization", `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floor1Id = jobRes.body.floors[0].id;

    const created = await request(app)
      .post("/api/seals")
      .set("Authorization", `Bearer ${workerToken}`)
      .send(sealBody(jobId, floor1Id, `${SEAL_PREFIX}1`));
    expect(created.status).toBe(201);
    sealId = created.body.id;

    await request(app)
      .patch(`/api/seals/${sealId}/review`)
      .set("Authorization", `Bearer ${managementToken}`)
      .send({ action: "returned", comment: "Opravit rozměr" })
      .expect(200);

    const manager = await prisma.user.findUnique({
      where: { username: "vedeni" },
    });
    const extraJob = await prisma.job.create({
      data: {
        projectNumber: `88${Date.now().toString().slice(-6)}`,
        name: "Stats worksheet filter",
        createdById: manager.id,
        participants: {
          create: {
            userId: workerId,
            roleOnJob: "worker",
            assignedById: manager.id,
          },
        },
      },
    });
    extraJobId = extraJob.id;

    const targetWorksheet = await prisma.workSheet.create({
      data: {
        jobId,
        createdById: workerId,
        workers: { create: { userId: workerId } },
      },
    });
    targetWorksheetId = targetWorksheet.id;

    const extraWorksheet = await prisma.workSheet.create({
      data: {
        jobId: extraJobId,
        createdById: workerId,
        workers: { create: { userId: workerId } },
      },
    });
    extraWorksheetId = extraWorksheet.id;

    const completedJob = await prisma.job.create({
      data: {
        projectNumber: `77${Date.now().toString().slice(-6)}`,
        name: "Stats completed job excluded",
        status: "completed",
        isArchived: true,
        createdById: manager.id,
        participants: {
          create: {
            userId: workerId,
            roleOnJob: "worker",
            assignedById: manager.id,
          },
        },
        floors: { create: { name: "1. NP", sortOrder: 1 } },
      },
      include: { floors: true },
    });
    completedJobId = completedJob.id;

    const completedSeal = await prisma.seal.create({
      data: {
        jobId: completedJob.id,
        floorId: completedJob.floors[0].id,
        sealNumber: `${SEAL_PREFIX}9`,
        trade: "elektrikari",
        system: "Stats inactive",
        construction: "Stěna",
        location: "Neaktivní",
        fireRating: "EI 60",
        createdById: workerId,
        entries: {
          create: {
            entryType: "EL.V.",
            electroInstallationType: "Svazek",
            dimension: "50",
            quantity: 1,
            insulation: "žádná",
            sortOrder: 0,
            materials: { create: { material: "Pěna", sortOrder: 0 } },
          },
        },
      },
    });
    completedSealId = completedSeal.id;

    const completedWorksheet = await prisma.workSheet.create({
      data: {
        jobId: completedJob.id,
        createdById: workerId,
        workers: { create: { userId: workerId } },
      },
    });
    completedWorksheetId = completedWorksheet.id;
  });

  afterAll(async () => {
    await prisma.workSheet.deleteMany({
      where: {
        id: {
          in: [
            targetWorksheetId,
            extraWorksheetId,
            completedWorksheetId,
          ].filter(Boolean),
        },
      },
    });
    if (completedSealId)
      await prisma.seal.delete({ where: { id: completedSealId } });
    if (extraJobId) await prisma.job.delete({ where: { id: extraJobId } });
    if (completedJobId) {
      await prisma.jobParticipant.deleteMany({
        where: { jobId: completedJobId },
      });
      await prisma.jobFloor.deleteMany({ where: { jobId: completedJobId } });
      await prisma.job.delete({ where: { id: completedJobId } });
    }
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.$disconnect();
  });

  it("vedení overview includes extended KPI fields", async () => {
    const res = await request(app)
      .get("/api/stats/overview")
      .set("Authorization", `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.body.role).toBe("vedeni");
    expect(res.body).toHaveProperty("returnedSeals");
    expect(res.body).toHaveProperty("missingPhotos");
    expect(res.body).toHaveProperty("syncPending");
    expect(res.body).toHaveProperty("byJobDetailed");
    expect(Array.isArray(res.body.byJobDetailed)).toBe(true);
    expect(res.body.returnedSeals).toBeGreaterThanOrEqual(1);
  });

  it("management overview excludes completed and archived jobs from active dashboard stats", async () => {
    const res = await request(app)
      .get("/api/stats/overview")
      .set("Authorization", `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.body.byJobDetailed.some((j) => j.jobId === completedJobId)).toBe(
      false,
    );
    expect(res.body.byJob.some((j) => j.jobId === completedJobId)).toBe(false);
    expect(res.body.totalSeals).toBeLessThan(
      await prisma.seal.count({ where: { deletedAt: null } }),
    );
    expect(res.body.worksheetCount).toBeLessThan(
      await prisma.workSheet.count(),
    );
  });

  it("management overview exposes completedArchivedJobs as the explicit exception KPI", async () => {
    const res = await request(app)
      .get("/api/stats/overview")
      .set("Authorization", `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    const expectedCount = await prisma.job.count({
      where: { deletedAt: null, status: { in: ["completed", "archived"] } },
    });
    expect(res.body.completedArchivedJobs).toBe(expectedCount);
    expect(res.body.completedArchivedJobs).toBeGreaterThanOrEqual(1);
  });

  it("filters by jobId reduce totals", async () => {
    const all = await request(app)
      .get("/api/stats/overview")
      .set("Authorization", `Bearer ${managementToken}`);
    const filtered = await request(app)
      .get(`/api/stats/overview?jobId=${jobId}`)
      .set("Authorization", `Bearer ${managementToken}`);

    expect(filtered.status).toBe(200);
    expect(filtered.body.filters.jobId).toBe(jobId);
    expect(filtered.body.totalSeals).toBeLessThanOrEqual(all.body.totalSeals);
    const jobRow = filtered.body.byJobDetailed.find((j) => j.jobId === jobId);
    expect(jobRow).toBeTruthy();
    expect(jobRow.returned).toBeGreaterThanOrEqual(1);
  });

  it("worker stats include returned and missing photos", async () => {
    const res = await request(app)
      .get("/api/stats/overview")
      .set("Authorization", `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(res.body.role).toBe("worker");
    expect(res.body.returnedForFix).toBeGreaterThanOrEqual(1);
    expect(res.body.missingPhotos).toBeGreaterThanOrEqual(1);
  });

  it("worker stats exclude completed and archived jobs", async () => {
    const res = await request(app)
      .get("/api/stats/overview")
      .set("Authorization", `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(res.body.byJob.some((j) => j.jobId === completedJobId)).toBe(false);
    expect(res.body.worksheetCount).toBeLessThan(
      await prisma.workSheet.count({
        where: { workers: { some: { userId: workerId } } },
      }),
    );
  });

  it("worker worksheet count respects job filter", async () => {
    const res = await request(app)
      .get(`/api/stats/overview?jobId=${jobId}`)
      .set("Authorization", `Bearer ${workerToken}`);

    const expected = await prisma.workSheet.count({
      where: { jobId, workers: { some: { userId: workerId } } },
    });
    const unfiltered = await prisma.workSheet.count({
      where: { workers: { some: { userId: workerId } } },
    });

    expect(res.status).toBe(200);
    expect(res.body.worksheetCount).toBe(expected);
    expect(res.body.worksheetCount).toBeLessThan(unfiltered);
  });

  it("status filter limits seal counts", async () => {
    const res = await request(app)
      .get(`/api/stats/overview?jobId=${jobId}&status=draft`)
      .set("Authorization", `Bearer ${managementToken}`);

    expect(res.status).toBe(200);
    expect(res.body.filters.status).toBe("draft");
    expect(res.body.checked).toBe(0);
    expect(res.body.invoiced).toBe(0);
  });
});
