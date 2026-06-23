import { describe, it, expect, beforeAll, afterAll } from "@jest/globals";
import request from "supertest";
import { createApp } from "../dist/app.js";
import { prisma } from "../dist/lib/prisma.js";

const SEAL_PREFIX = "991";

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: "elektrikari",
    system: "WSL",
    construction: "Stěna",
    location: "Test",
    fireRating: "EI 60",
    entries: [
      {
        entryType: "EL.V.",
        electroInstallationType: "Svazek",
        dimension: "50",
        quantity: 1,
        insulation: "žádná",
        materials: ["Pěna"],
      },
    ],
  };
}

describe("Worksheet membership + seal lock", () => {
  const app = createApp();
  let workerToken;
  let worker2Token;
  let vedeniToken;
  let adminToken;
  let jobId;
  let floorId;
  let sealId;
  let worksheetId;

  async function login(username) {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username, pin: "123456" });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login("worker1");
    worker2Token = await login("worker2");
    vedeniToken = await login("vedeni");
    adminToken = await login("admin");

    const jobRes = await request(app)
      .get("/api/jobs/by-number/12345678")
      .set("Authorization", `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;

    const worker2 = await prisma.user.findUnique({
      where: { username: "worker2" },
    });
    const vedeni = await prisma.user.findUnique({
      where: { username: "vedeni" },
    });
    await prisma.jobParticipant.upsert({
      where: { jobId_userId: { jobId, userId: worker2.id } },
      create: {
        jobId,
        userId: worker2.id,
        roleOnJob: "worker",
        assignedById: vedeni.id,
      },
      update: { roleOnJob: "worker" },
    });

    const sealRes = await request(app)
      .post("/api/seals")
      .set("Authorization", `Bearer ${workerToken}`)
      .send(sealBody(jobId, floorId, `${SEAL_PREFIX}01`));
    expect(sealRes.status).toBe(201);
    sealId = sealRes.body.id;
  });

  afterAll(async () => {
    if (worksheetId) {
      await prisma.workSheetItem.deleteMany({ where: { worksheetId } });
      await prisma.workSheet.deleteMany({ where: { id: worksheetId } });
    }
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    await prisma.$disconnect();
  });

  it("populate returns requested/added counts and skips already-claimed entries", async () => {
    const wsRes = await request(app)
      .post("/api/worksheets")
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ jobId });
    expect(wsRes.status).toBe(201);
    worksheetId = wsRes.body.id;

    const pop = await request(app)
      .post(`/api/worksheets/${worksheetId}/populate`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({});
    expect(pop.status).toBe(201);
    expect(pop.body.requestedCount).toBeGreaterThanOrEqual(1);
    expect(pop.body.addedCount).toBe(pop.body.requestedCount);

    // Druhý populate už nic nepřidá (vše je v soupisu) a neshodí se na 400.
    const wsRes2 = await request(app)
      .post("/api/worksheets")
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ jobId });
    expect(wsRes2.status).toBe(201);
    const pop2 = await request(app)
      .post(`/api/worksheets/${wsRes2.body.id}/populate`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({});
    expect(pop2.status).toBe(201);
    expect(pop2.body.addedCount).toBe(0);
    await prisma.workSheet.deleteMany({ where: { id: wsRes2.body.id } });
  });

  it("GET seal exposes worksheet membership per entry", async () => {
    const res = await request(app)
      .get(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    const entry = res.body.entries[0];
    expect(entry.worksheet).toBeTruthy();
    expect(entry.worksheet.worksheetId).toBe(worksheetId);
    expect(entry.worksheet.status).toBe("draft");
  });

  it("GET seal hides owner and worksheet membership from another worker", async () => {
    const res = await request(app)
      .get(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${worker2Token}`);

    expect(res.status).toBe(200);
    expect(res.body.createdBy).toBeUndefined();
    expect(res.body.entries[0].worksheet).toBeNull();
  });

  it("seal entries editable while worksheet is draft", async () => {
    // Editace prostupů u draft soupisu projde (soupis ještě nezamyká).
    // Pozn.: necháváme původní prostup beze změny, aby zůstal navázaný na soupis
    // pro následný test zámku po odevzdání – ověříme jen, že request projde.
    const current = await request(app)
      .get(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`);
    const patch = await request(app)
      .patch(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ baseVersion: current.body.version, note: "pozn. draft" });
    expect(patch.status).toBe(200);
  });

  it("blocks seal entry edits once worksheet is submitted; admin can override", async () => {
    const submit = await request(app)
      .patch(`/api/worksheets/${worksheetId}/status`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ status: "submitted" });
    expect(submit.status).toBe(200);

    const current = await request(app)
      .get(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`);

    const blocked = await request(app)
      .patch(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({
        baseVersion: current.body.version,
        entries: [
          {
            entryType: "EL.V.",
            electroInstallationType: "Svazek",
            dimension: "70",
            quantity: 1,
            insulation: "žádná",
            materials: ["Pěna"],
          },
        ],
      });
    expect(blocked.status).toBe(403);
    expect(blocked.body.error).toMatch(/soupis/i);

    // Úprava bez prostupů (jen poznámka) projde i u odevzdaného soupisu.
    const noteOnly = await request(app)
      .patch(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${vedeniToken}`)
      .send({ baseVersion: current.body.version, note: "Pozn. vedení" });
    expect(noteOnly.status).toBe(200);

    // Admin s důvodem může prostupy přepsat (override_locked).
    const after = await request(app)
      .get(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${adminToken}`);
    const override = await request(app)
      .patch(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        baseVersion: after.body.version,
        overrideReason: "Oprava po odevzdání",
        entries: [
          {
            entryType: "EL.V.",
            electroInstallationType: "Svazek",
            dimension: "80",
            quantity: 1,
            insulation: "žádná",
            materials: ["Pěna"],
          },
        ],
      });
    expect(override.status).toBe(200);
  });
});

describe("Restructured log endpoints", () => {
  const app = createApp();
  let workerToken;
  let vedeniToken;
  let adminToken;

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
    adminToken = await login("admin");
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it("my-activity is available to every authenticated role", async () => {
    for (const token of [workerToken, vedeniToken, adminToken]) {
      const res = await request(app)
        .get("/api/logs/my-activity")
        .set("Authorization", `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
    }
  });

  it("history is available to vedeni/admin but not worker", async () => {
    const worker = await request(app)
      .get("/api/logs/history")
      .set("Authorization", `Bearer ${workerToken}`);
    expect(worker.status).toBe(403);

    for (const token of [vedeniToken, adminToken]) {
      const res = await request(app)
        .get("/api/logs/history")
        .set("Authorization", `Bearer ${token}`);
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
    }
  });

  it("user-activity requires logs.view (vedeni/admin)", async () => {
    const worker = await request(app)
      .get("/api/logs/user-activity")
      .set("Authorization", `Bearer ${workerToken}`);
    expect(worker.status).toBe(403);

    const vedeni = await request(app)
      .get("/api/logs/user-activity")
      .set("Authorization", `Bearer ${vedeniToken}`);
    expect(vedeni.status).toBe(200);
  });

  it("system is admin-only", async () => {
    const vedeni = await request(app)
      .get("/api/logs/system")
      .set("Authorization", `Bearer ${vedeniToken}`);
    expect(vedeni.status).toBe(403);

    const admin = await request(app)
      .get("/api/logs/system")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(admin.status).toBe(200);
    expect(Array.isArray(admin.body)).toBe(true);
  });
});
