import { describe, it, expect, beforeAll } from "@jest/globals";
import request from "supertest";
import { createApp } from "../dist/app.js";
import { prisma } from "../dist/lib/prisma.js";

describe("Worksheet access (wave 2)", () => {
  const app = createApp();
  let worker1Token;
  let worker2Token;
  let vedeniToken;
  let jobId;
  let floorId;
  let foreignWorksheetId;

  async function login(username) {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username, pin: "123456" });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    worker1Token = await login("worker1");
    worker2Token = await login("worker2");
    vedeniToken = await login("vedeni");

    const jobRes = await request(app)
      .get("/api/jobs/by-number/12345678")
      .set("Authorization", `Bearer ${worker1Token}`);
    jobId = jobRes.body.id;
    floorId = jobRes.body.floors[0].id;

    const worker2Participant = await request(app)
      .post(`/api/jobs/${jobId}/participants`)
      .set("Authorization", `Bearer ${vedeniToken}`)
      .send({ userId: await workerId("worker2"), roleOnJob: "worker" });
    expect(worker2Participant.status).toBe(201);

    const ws = await request(app)
      .post("/api/worksheets")
      .set("Authorization", `Bearer ${vedeniToken}`)
      .send({ jobId, workerIds: [await workerId("worker1")] });
    expect(ws.status).toBe(201);
    foreignWorksheetId = ws.body.id;
  });

  async function workerId(username) {
    const user = await prisma.user.findUnique({ where: { username } });
    if (!user) throw new Error(`User ${username} not found`);
    return user.id;
  }

  it("worker2 cannot add items to worker1-only draft worksheet", async () => {
    const seal = await request(app)
      .post("/api/seals")
      .set("Authorization", `Bearer ${worker2Token}`)
      .send({
        jobId,
        floorId,
        sealNumber: `${Date.now()}`.slice(-4),
        trade: "elektrikari",
        system: "WS",
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
            materials: ["Pena"],
          },
        ],
      });
    expect(seal.status).toBe(201);
    const entryId = seal.body.entries[0].id;

    const add = await request(app)
      .post(`/api/worksheets/${foreignWorksheetId}/items`)
      .set("Authorization", `Bearer ${worker2Token}`)
      .send({ sealEntryIds: [entryId] });
    expect(add.status).toBe(403);
  });

  it("reports PDF without jobId returns 400", async () => {
    const res = await request(app)
      .get("/api/reports/export/pdf")
      .set("Authorization", `Bearer ${vedeniToken}`);
    expect(res.status).toBe(400);
  });
});
