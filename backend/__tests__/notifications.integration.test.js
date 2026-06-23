import { describe, it, expect, beforeAll, afterAll } from "@jest/globals";
import request from "supertest";
import { createApp } from "../dist/app.js";
import { prisma } from "../dist/lib/prisma.js";

describe("Notifications integration", () => {
  const app = createApp();
  let worker1Token;
  let worker2Token;
  let worker1Id;
  let worker2Id;
  let activeJobId;
  let inactiveJobId;
  const notificationIds = [];

  async function login(username) {
    const res = await request(app)
      .post("/api/auth/login")
      .send({ username, pin: "123456" });
    expect(res.status).toBe(200);
    return res.body;
  }

  beforeAll(async () => {
    const worker1 = await login("worker1");
    const worker2 = await login("worker2");
    worker1Token = worker1.token;
    worker2Token = worker2.token;
    worker1Id = worker1.user.id;
    worker2Id = worker2.user.id;

    const job = await request(app)
      .get("/api/jobs/by-number/12345678")
      .set("Authorization", `Bearer ${worker1Token}`);
    expect(job.status).toBe(200);
    activeJobId = job.body.id;

    const manager = await prisma.user.findUnique({
      where: { username: "vedeni" },
    });
    const inactiveJob = await prisma.job.create({
      data: {
        projectNumber: `65${Date.now().toString().slice(-6)}`,
        name: "Notifications inactive job",
        status: "completed",
        isArchived: true,
        createdById: manager.id,
      },
    });
    inactiveJobId = inactiveJob.id;

    const rows = await prisma.notification.createManyAndReturn({
      data: [
        {
          userId: worker1Id,
          type: "test",
          title: "Aktivní zakázka",
          body: "Viditelné",
          entityType: "job",
          entityId: activeJobId,
        },
        {
          userId: worker1Id,
          type: "test",
          title: "Dokončená zakázka",
          body: "Skryté",
          entityType: "job",
          entityId: inactiveJobId,
        },
        {
          userId: worker2Id,
          type: "test",
          title: "Cizí notifikace",
          body: "Zůstane nepřečtená",
          entityType: "job",
          entityId: activeJobId,
        },
      ],
    });
    notificationIds.push(...rows.map((row) => row.id));
  });

  afterAll(async () => {
    await prisma.notification.deleteMany({
      where: { id: { in: notificationIds } },
    });
    if (inactiveJobId)
      await prisma.job.delete({ where: { id: inactiveJobId } });
    await prisma.$disconnect();
  });

  it("lists and counts only job notifications from active jobs", async () => {
    const list = await request(app)
      .get("/api/notifications")
      .set("Authorization", `Bearer ${worker1Token}`);
    expect(list.status).toBe(200);
    expect(list.body.some((n) => n.entityId === activeJobId)).toBe(true);
    expect(list.body.some((n) => n.entityId === inactiveJobId)).toBe(false);

    const unread = await request(app)
      .get("/api/notifications/unread-count")
      .set("Authorization", `Bearer ${worker1Token}`);
    expect(unread.status).toBe(200);
    expect(unread.body.count).toBeGreaterThanOrEqual(1);
    expect(unread.body.count).toBeLessThan(
      await prisma.notification.count({
        where: { userId: worker1Id, readAt: null },
      }),
    );
  });

  it("mark all as read only affects the current user", async () => {
    const res = await request(app)
      .patch("/api/notifications/read-all")
      .set("Authorization", `Bearer ${worker1Token}`);
    expect(res.status).toBe(200);

    const worker1Unread = await prisma.notification.count({
      where: { id: { in: notificationIds }, userId: worker1Id, readAt: null },
    });
    const worker2Unread = await prisma.notification.count({
      where: { id: { in: notificationIds }, userId: worker2Id, readAt: null },
    });
    expect(worker1Unread).toBe(0);
    expect(worker2Unread).toBe(1);

    const worker2List = await request(app)
      .get("/api/notifications")
      .set("Authorization", `Bearer ${worker2Token}`);
    expect(worker2List.status).toBe(200);
    expect(worker2List.body.some((n) => n.userId === worker1Id)).toBe(false);
  });
});
