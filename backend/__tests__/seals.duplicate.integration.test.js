import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const TEST_SEAL_NUMBER = 'DB01-DUP-TEST';

function sealPayload(jobId, floorId, userId, sealNumber = TEST_SEAL_NUMBER) {
  return {
    jobId,
    floorId,
    sealNumber,
    trade: 'elektrikari',
    system: 'Zkušební',
    construction: 'Stěna',
    location: 'Chodba',
    fireRating: 'EI 60',
    createdById: userId,
  };
}

describe('seals partial unique index (DB-01)', () => {
  let jobId;
  let floorId;
  let floor2Id;
  let userId;

  beforeAll(async () => {
    const job = await prisma.job.findFirst({
      where: { projectNumber: '12345678', deletedAt: null },
    });
    expect(job).toBeTruthy();

    const floors = await prisma.jobFloor.findMany({
      where: { jobId: job.id, deletedAt: null },
      orderBy: { sortOrder: 'asc' },
    });
    expect(floors.length).toBeGreaterThanOrEqual(2);

    const user = await prisma.user.findFirst({ where: { username: 'worker1' } });
    expect(user).toBeTruthy();

    jobId = job.id;
    floorId = floors[0].id;
    floor2Id = floors[1].id;
    userId = user.id;
  });

  afterAll(async () => {
    await prisma.seal.deleteMany({ where: { sealNumber: TEST_SEAL_NUMBER } });
    await prisma.$disconnect();
  });

  it('rejects two active seals with the same number on the same floor', async () => {
    const first = await prisma.seal.create({
      data: sealPayload(jobId, floorId, userId),
    });

    await expect(
      prisma.seal.create({ data: sealPayload(jobId, floorId, userId) }),
    ).rejects.toMatchObject({ code: 'P2002' });

    await prisma.seal.delete({ where: { id: first.id } });
  });

  it('allows the same number after soft delete of the previous seal', async () => {
    const deleted = await prisma.seal.create({
      data: sealPayload(jobId, floorId, userId),
    });

    await prisma.seal.update({
      where: { id: deleted.id },
      data: { deletedAt: new Date(), deletedById: userId, deleteReason: 'test' },
    });

    const replacement = await prisma.seal.create({
      data: sealPayload(jobId, floorId, userId),
    });

    expect(replacement.id).not.toBe(deleted.id);
    expect(replacement.deletedAt).toBeNull();

    await prisma.seal.deleteMany({ where: { sealNumber: TEST_SEAL_NUMBER } });
  });

  it('allows the same number on a different floor', async () => {
    const onFloor1 = await prisma.seal.create({
      data: sealPayload(jobId, floorId, userId),
    });
    const onFloor2 = await prisma.seal.create({
      data: sealPayload(jobId, floor2Id, userId),
    });

    expect(onFloor1.id).not.toBe(onFloor2.id);

    await prisma.seal.deleteMany({ where: { sealNumber: TEST_SEAL_NUMBER } });
  });
});
