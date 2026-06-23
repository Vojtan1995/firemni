import { describe, it, expect, beforeAll, afterAll } from "@jest/globals";
import request from "supertest";
import { createApp } from "../dist/app.js";
import { prisma } from "../dist/lib/prisma.js";

describe("Search API", () => {
  const app = createApp();
  let workerToken;
  let vedeniToken;
  let inactiveJobId;
  let inactiveSealId;

  async function login(username) {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username, pin: "123456" });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login("worker1");
    vedeniToken = await login("vedeni");

    const manager = await prisma.user.findUnique({
      where: { username: "vedeni" },
    });
    const worker = await prisma.user.findUnique({
      where: { username: "worker1" },
    });
    const inactiveJob = await prisma.job.create({
      data: {
        projectNumber: `66${Date.now().toString().slice(-6)}`,
        name: "Search inactive action",
        status: "completed",
        isArchived: true,
        createdById: manager.id,
        floors: { create: { name: "1. NP", sortOrder: 1 } },
      },
      include: { floors: true },
    });
    inactiveJobId = inactiveJob.id;
    const inactiveSeal = await prisma.seal.create({
      data: {
        jobId: inactiveJob.id,
        floorId: inactiveJob.floors[0].id,
        sealNumber: `srch${Date.now().toString().slice(-5)}`,
        trade: "elektrikari",
        system: "InactiveSearch",
        construction: "Stěna",
        location: "Dokončeno",
        fireRating: "EI 60",
        reviewStatus: "returned",
        createdById: worker.id,
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
    inactiveSealId = inactiveSeal.id;
  });

  afterAll(async () => {
    if (inactiveSealId)
      await prisma.seal.delete({ where: { id: inactiveSealId } });
    if (inactiveJobId) {
      await prisma.jobFloor.deleteMany({ where: { jobId: inactiveJobId } });
      await prisma.job.delete({ where: { id: inactiveJobId } });
    }
    await prisma.$disconnect();
  });

  it("rejects empty query without filters", async () => {
    const res = await request(app)
      .get("/api/search")
      .set("Authorization", `Bearer ${workerToken}`);
    expect(res.status).toBe(400);
  });

  it("worker finds demo job by project number", async () => {
    const res = await request(app)
      .get("/api/search?q=12345678")
      .set("Authorization", `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.items.some((i) => i.type === "job")).toBe(true);
  });

  it("vedeni can filter returned seals", async () => {
    const res = await request(app)
      .get("/api/search?filters=awaiting_review&limit=5")
      .set("Authorization", `Bearer ${vedeniToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.items)).toBe(true);
  });

  it("action filters exclude seals from completed and archived jobs", async () => {
    const res = await request(app)
      .get("/api/search?filters=returned&limit=50")
      .set("Authorization", `Bearer ${vedeniToken}`);

    expect(res.status).toBe(200);
    expect(res.body.items.some((i) => i.id === inactiveSealId)).toBe(false);
  });
});
