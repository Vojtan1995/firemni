import { describe, it, expect, beforeAll, afterAll, jest } from "@jest/globals";
import request from "supertest";
import { createApp } from "../dist/app.js";
import { prisma } from "../dist/lib/prisma.js";

const SEAL_PREFIX = "8860";
const tinyPng = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
  "base64",
);
const tinyJpeg = Buffer.from(
  "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA//2Q==",
  "base64",
);

function sealBody(jobId, floorId, sealNumber) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: "elektrikari",
    system: "Plan",
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

describe("Floor drawings and markers (task 5.3)", () => {
  const app = createApp();
  let workerToken;
  let managementToken;
  let jobId;
  let floor1Id;
  let floor2Id;
  let replacementFloorId;
  let sealId;

  async function login(username) {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username, pin: "123456" });
    expect(res.status).toBe(200);
    return res.body.token;
  }

  beforeAll(async () => {
    workerToken = await login("worker1");
    managementToken = await login("vedeni");

    const jobRes = await request(app)
      .get("/api/jobs/by-number/12345678")
      .set("Authorization", `Bearer ${workerToken}`);
    jobId = jobRes.body.id;
    floor1Id = jobRes.body.floors[0].id;
    floor2Id = jobRes.body.floors[1]?.id ?? jobRes.body.floors[0].id;

    const created = await request(app)
      .post("/api/seals")
      .set("Authorization", `Bearer ${workerToken}`)
      .send(sealBody(jobId, floor1Id, `${SEAL_PREFIX}1`));
    expect(created.status).toBe(201);
    sealId = created.body.id;

    const replacementFloor = await request(app)
      .post(`/api/jobs/${jobId}/floors`)
      .set("Authorization", `Bearer ${managementToken}`)
      .send({ name: `Replacement ${SEAL_PREFIX}` });
    expect(replacementFloor.status).toBe(201);
    replacementFloorId = replacementFloor.body.id;
  });

  afterAll(async () => {
    await prisma.sealMarker.deleteMany({
      where: { seal: { sealNumber: { startsWith: SEAL_PREFIX } } },
    });
    await prisma.floorDrawing.deleteMany({
      where: {
        floorId: {
          in: [floor1Id, floor2Id, replacementFloorId].filter(Boolean),
        },
      },
    });
    await prisma.seal.deleteMany({
      where: { sealNumber: { startsWith: SEAL_PREFIX } },
    });
    if (replacementFloorId) {
      await prisma.jobFloor.deleteMany({ where: { id: replacementFloorId } });
    }
    await prisma.$disconnect();
  });

  it("vedení can upload floor drawing and preserve original PNG", async () => {
    const res = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`)
      .attach("drawing", tinyPng, {
        filename: "plan.png",
        contentType: "image/png",
      });

    expect(res.status).toBe(201);
    expect(res.body.mimeType).toBe("image/png");
    expect(res.body.width).toBeGreaterThan(0);
    expect(res.body.height).toBeGreaterThan(0);

    const file = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/file`)
      .set("Authorization", `Bearer ${workerToken}`);

    expect(file.status).toBe(200);
    expect(file.headers["content-type"]).toMatch(/image\/png/);
    expect(Buffer.compare(file.body, tinyPng)).toBe(0);
  });

  it("vedení can upload JPEG floor drawing without WebP conversion", async () => {
    const res = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`)
      .attach("drawing", tinyJpeg, {
        filename: "plan.jpg",
        contentType: "image/jpeg",
      });

    expect(res.status).toBe(201);
    expect(res.body.mimeType).toBe("image/jpeg");

    const file = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/file`)
      .set("Authorization", `Bearer ${workerToken}`);

    expect(file.status).toBe(200);
    expect(file.headers["content-type"]).toMatch(/image\/jpeg/);
    expect(Buffer.compare(file.body, tinyJpeg)).toBe(0);
  });

  it("worker cannot upload drawing", async () => {
    const res = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${workerToken}`)
      .attach("drawing", tinyPng, {
        filename: "plan.png",
        contentType: "image/png",
      });

    expect(res.status).toBe(403);
  });

  it("vedeni can upload and delete floor drawing", async () => {
    const upload = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor2Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`)
      .attach("drawing", tinyPng, {
        filename: "plan.png",
        contentType: "image/png",
      });

    expect(upload.status).toBe(201);

    const del = await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor2Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`);

    expect(del.status).toBe(200);
    expect(del.body.ok).toBe(true);
  });

  it("rolls back new file and keeps previous drawing when DB write fails", async () => {
    // Nahraj výchozí výkres (JPEG) na floor2.
    const first = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor2Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`)
      .attach("drawing", tinyJpeg, {
        filename: "orig.jpg",
        contentType: "image/jpeg",
      });
    expect(first.status).toBe(201);

    // Vynuť selhání DB zápisu při dalším uploadu.
    const spy = jest
      .spyOn(prisma, "$transaction")
      .mockRejectedValueOnce(new Error("simulované selhání DB"));

    const failed = await request(app)
      .post(`/api/jobs/${jobId}/floors/${floor2Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`)
      .attach("drawing", tinyPng, {
        filename: "novy.png",
        contentType: "image/png",
      });
    expect(failed.status).toBeGreaterThanOrEqual(500);

    spy.mockRestore();

    // Předchozí výkres (JPEG) musí být stále dostupný — starý soubor se nesmazal.
    const file = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor2Id}/drawing/file`)
      .set("Authorization", `Bearer ${workerToken}`);
    expect(file.status).toBe(200);
    expect(file.headers["content-type"]).toMatch(/image\/jpeg/);
    expect(Buffer.compare(file.body, tinyJpeg)).toBe(0);

    // Úklid.
    await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor2Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`);
  });

  it("floors list includes hasDrawing flag", async () => {
    const res = await request(app)
      .get(`/api/jobs/${jobId}/floors`)
      .set("Authorization", `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(res.body.length).toBeGreaterThan(0);
    expect(typeof res.body[0].hasDrawing).toBe("boolean");
    expect(res.body.some((f) => f.hasDrawing === true)).toBe(true);
  });

  it("export pdf accepts sealIds and reviewStatus filters", async () => {
    const bySeal = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/export/pdf`)
      .query({ sealIds: sealId })
      .set("Authorization", `Bearer ${managementToken}`);

    expect(bySeal.status).toBe(200);
    expect(bySeal.headers["content-type"]).toMatch(/application\/pdf/);

    const byReview = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/export/pdf`)
      .query({ reviewStatus: "returned" })
      .set("Authorization", `Bearer ${managementToken}`);

    expect(byReview.status).toBe(200);
    expect(byReview.headers["content-type"]).toMatch(/application\/pdf/);
  });

  it("returns drawing bundle with file endpoint", async () => {
    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${workerToken}`);

    expect(bundle.status).toBe(200);
    expect(bundle.body.drawing).toBeTruthy();

    const file = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing/file`)
      .set("Authorization", `Bearer ${workerToken}`);

    expect(file.status).toBe(200);
    expect(file.headers["content-type"]).toMatch(/image\/(png|jpeg|webp)/);
  });

  it("worker can place and read seal marker", async () => {
    const put = await request(app)
      .put(`/api/jobs/${jobId}/floors/${floor1Id}/markers/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ x: 0.42, y: 0.58 });

    expect(put.status).toBe(200);
    expect(put.body.x).toBeCloseTo(0.42);
    expect(put.body.y).toBeCloseTo(0.58);

    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`);

    expect(bundle.body.markers).toHaveLength(1);
    expect(bundle.body.markers[0].sealNumber).toBe(`${SEAL_PREFIX}1`);
    expect(bundle.body.markers[0].createdById).toBeTruthy();
    expect(bundle.body.markers[0].createdByName).toBeTruthy();
  });

  it("marker label offset round-trips and is preserved when only the point moves", async () => {
    // Reuses the marker placed by the previous test (x: 0.42, y: 0.58) and
    // restores those coordinates afterwards so later tests relying on this
    // shared sealId/marker aren't affected.
    const put = await request(app)
      .put(`/api/jobs/${jobId}/floors/${floor1Id}/markers/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ x: 0.42, y: 0.58, labelOffsetX: 0.1, labelOffsetY: -0.05 });

    expect(put.status).toBe(200);
    expect(put.body.labelOffsetX).toBeCloseTo(0.1);
    expect(put.body.labelOffsetY).toBeCloseTo(-0.05);

    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`);
    const marker = bundle.body.markers.find((m) => m.sealId === sealId);
    expect(marker.labelOffsetX).toBeCloseTo(0.1);
    expect(marker.labelOffsetY).toBeCloseTo(-0.05);

    // Moving just the point (no offset in payload) must not wipe the label offset.
    const move = await request(app)
      .put(`/api/jobs/${jobId}/floors/${floor1Id}/markers/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ x: 0.42, y: 0.58 });
    expect(move.status).toBe(200);
    expect(move.body.x).toBeCloseTo(0.42);
    expect(move.body.labelOffsetX).toBeCloseTo(0.1);
    expect(move.body.labelOffsetY).toBeCloseTo(-0.05);
  });

  it("replacing a drawing clears old markers and marks seals for placement", async () => {
    const localSealNumber = `${SEAL_PREFIX}9`;
    const created = await request(app)
      .post("/api/seals")
      .set("Authorization", `Bearer ${workerToken}`)
      .send(sealBody(jobId, replacementFloorId, localSealNumber));
    expect(created.status).toBe(201);

    const first = await request(app)
      .post(`/api/jobs/${jobId}/floors/${replacementFloorId}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`)
      .attach("drawing", tinyPng, {
        filename: "original.png",
        contentType: "image/png",
      });
    expect(first.status).toBe(201);

    const marker = await request(app)
      .put(
        `/api/jobs/${jobId}/floors/${replacementFloorId}/markers/${created.body.id}`,
      )
      .set("Authorization", `Bearer ${workerToken}`)
      .send({ x: 0.4, y: 0.6 });
    expect(marker.status).toBe(200);

    const replacement = await request(app)
      .post(`/api/jobs/${jobId}/floors/${replacementFloorId}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`)
      .attach("drawing", tinyJpeg, {
        filename: "replacement.jpg",
        contentType: "image/jpeg",
      });
    expect(replacement.status).toBe(201);

    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${replacementFloorId}/drawing`)
      .set("Authorization", `Bearer ${workerToken}`);
    expect(bundle.status).toBe(200);
    expect(bundle.body.markers).toHaveLength(0);

    const seal = await prisma.seal.findUnique({
      where: { id: created.body.id },
      select: { markerPlacementPending: true },
    });
    expect(seal?.markerPlacementPending).toBe(true);
  });

  it("sync pull includes drawings and markers", async () => {
    const res = await request(app)
      .get("/api/sync/pull")
      .set("Authorization", `Bearer ${workerToken}`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.floorDrawings)).toBe(true);
    expect(Array.isArray(res.body.sealMarkers)).toBe(true);
    expect(res.body.sealMarkers.some((m) => m.sealId === sealId)).toBe(true);
  });

  it("returns next seal number and placement stats", async () => {
    const next = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/next-seal-number`)
      .set("Authorization", `Bearer ${workerToken}`);
    expect(next.status).toBe(200);
    // suggestNextSealNumber vrací nejmenší volné kladné číslo na patře (ne max+1).
    // Toto patro je sdílené demo patro, takže se nezávisíme na konkrétní hodnotě –
    // dedikované scénáře pokrývá seal-number-suggest.integration.test.js.
    expect(
      Number.parseInt(next.body.nextSealNumber, 10),
    ).toBeGreaterThanOrEqual(1);

    const stats = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/placement-stats`)
      .set("Authorization", `Bearer ${workerToken}`);
    expect(stats.status).toBe(200);
    expect(stats.body.total).toBeGreaterThanOrEqual(1);
    expect(stats.body.placed).toBeGreaterThanOrEqual(1);
    expect(stats.body.unplaced).toBeGreaterThanOrEqual(0);
  });

  it("seal detail includes marker coordinates", async () => {
    const res = await request(app)
      .get(`/api/seals/${sealId}`)
      .set("Authorization", `Bearer ${workerToken}`);
    expect(res.status).toBe(200);
    expect(res.body.marker).toBeTruthy();
    expect(res.body.marker.x).toBeCloseTo(0.42);
    expect(res.body.marker.y).toBeCloseTo(0.58);
  });

  it("sync push accepts seal_marker update", async () => {
    const mutationId = crypto.randomUUID();
    const res = await request(app)
      .post("/api/sync/push")
      .set("Authorization", `Bearer ${workerToken}`)
      .send({
        mutations: [
          {
            mutationId,
            deviceId: "test-device",
            entityType: "seal_marker",
            operation: "update",
            payload: { sealId, floorId: floor1Id, x: 0.1, y: 0.2 },
          },
        ],
      });

    expect(res.status).toBe(200);
    expect(res.body.results[0].status).toBe("ok");
  });

  it("sync push handles a marker queued before its new seal", async () => {
    const floorRes = await request(app)
      .post(`/api/jobs/${jobId}/floors`)
      .set("Authorization", `Bearer ${managementToken}`)
      .send({ name: `Queued marker ${SEAL_PREFIX}` });
    expect(floorRes.status).toBe(201);
    const localFloorId = floorRes.body.id;
    const localSealId = crypto.randomUUID();
    const sealNumber = `${SEAL_PREFIX}71`;

    try {
      const upload = await request(app)
        .post(`/api/jobs/${jobId}/floors/${localFloorId}/drawing`)
        .set("Authorization", `Bearer ${managementToken}`)
        .attach("drawing", tinyPng, {
          filename: "plan.png",
          contentType: "image/png",
        });
      expect(upload.status).toBe(201);

      const markerMutationId = crypto.randomUUID();
      const sealMutationId = crypto.randomUUID();
      const res = await request(app)
        .post("/api/sync/push")
        .set("Authorization", `Bearer ${workerToken}`)
        .send({
          mutations: [
            {
              mutationId: markerMutationId,
              deviceId: "test-device",
              entityType: "seal_marker",
              operation: "update",
              payload: {
                sealId: localSealId,
                floorId: localFloorId,
                x: 0.25,
                y: 0.75,
              },
            },
            {
              mutationId: sealMutationId,
              deviceId: "test-device",
              entityType: "seal",
              operation: "create",
              payload: {
                id: localSealId,
                ...sealBody(jobId, localFloorId, sealNumber),
                markerPlacementPending: false,
              },
            },
          ],
        });

      expect(res.status).toBe(200);
      expect(res.body.results).toHaveLength(2);
      expect(res.body.results[0]).toMatchObject({
        mutationId: markerMutationId,
        status: "ok",
        entityId: localSealId,
      });
      expect(res.body.results[1]).toMatchObject({
        mutationId: sealMutationId,
        status: "ok",
        entityId: localSealId,
      });

      const seal = await prisma.seal.findUnique({
        where: { id: localSealId },
        include: { marker: true },
      });
      expect(seal).toBeTruthy();
      expect(seal.markerPlacementPending).toBe(false);
      expect(seal.marker).toMatchObject({
        floorId: localFloorId,
        x: 0.25,
        y: 0.75,
      });
    } finally {
      await prisma.seal.deleteMany({ where: { id: localSealId } });
      await prisma.floorDrawing.deleteMany({ where: { floorId: localFloorId } });
      await prisma.jobFloor.deleteMany({ where: { id: localFloorId } });
    }
  });

  it("marks a new seal as placement-pending when the floor has a drawing", async () => {
    const floorRes = await request(app)
      .post(`/api/jobs/${jobId}/floors`)
      .set("Authorization", `Bearer ${managementToken}`)
      .send({ name: `Pending marker ${SEAL_PREFIX}` });
    expect(floorRes.status).toBe(201);
    const localFloorId = floorRes.body.id;
    const sealNumber = `${SEAL_PREFIX}72`;

    try {
      const upload = await request(app)
        .post(`/api/jobs/${jobId}/floors/${localFloorId}/drawing`)
        .set("Authorization", `Bearer ${managementToken}`)
        .attach("drawing", tinyPng, {
          filename: "plan.png",
          contentType: "image/png",
        });
      expect(upload.status).toBe(201);

      const created = await request(app)
        .post("/api/seals")
        .set("Authorization", `Bearer ${workerToken}`)
        .send({
          ...sealBody(jobId, localFloorId, sealNumber),
          markerPlacementPending: false,
        });
      expect(created.status).toBe(201);

      const seal = await prisma.seal.findUnique({
        where: { id: created.body.id },
        select: { markerPlacementPending: true },
      });
      expect(seal?.markerPlacementPending).toBe(true);
    } finally {
      await prisma.seal.deleteMany({ where: { sealNumber } });
      await prisma.floorDrawing.deleteMany({ where: { floorId: localFloorId } });
      await prisma.jobFloor.deleteMany({ where: { id: localFloorId } });
    }
  });

  it("vedení can delete marker and drawing", async () => {
    const delMarker = await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor1Id}/markers/${sealId}`)
      .set("Authorization", `Bearer ${managementToken}`);
    expect(delMarker.status).toBe(200);

    const delDrawing = await request(app)
      .delete(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${managementToken}`);
    expect(delDrawing.status).toBe(200);
    expect(delDrawing.body.ok).toBe(true);

    const bundle = await request(app)
      .get(`/api/jobs/${jobId}/floors/${floor1Id}/drawing`)
      .set("Authorization", `Bearer ${workerToken}`);
    expect(bundle.body.drawing).toBeNull();
  });
});
