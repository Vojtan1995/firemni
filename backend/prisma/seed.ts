import { PrismaClient, UserRole } from '@prisma/client';
import bcrypt from 'bcrypt';
import { seedDefaultPriceList } from '../src/services/pricing.service.js';

const prisma = new PrismaClient();

function resolveSeedPin(): string {
  const envPin = process.env.SEED_DEMO_PIN;
  if (envPin) return envPin;
  if (process.env.NODE_ENV === 'production') {
    throw new Error('SEED_DEMO_PIN must be set when seeding in production');
  }
  return '123456';
}

const DEMO_USERNAMES = ['admin', 'vedeni', 'ucetni', 'worker1', 'worker2'];

async function main() {
  const pinHash = await bcrypt.hash(resolveSeedPin(), 10);

  if (process.env.NODE_ENV === 'test') {
    // Vyčisti staré LoginLog záznamy, aby předchozí neúspěšné pokusy nezpůsobily lockout (DB-01)
    await prisma.loginLog.deleteMany({ where: { username: { in: DEMO_USERNAMES } } });
  }

  const admin = await prisma.user.upsert({
    where: { username: 'admin' },
    update: { pinHash, mustChangePin: true },
    create: {
      username: 'admin',
      displayName: 'Administrátor',
      pinHash,
      role: UserRole.admin,
      mustChangePin: true,
    },
  });

  const vedeni = await prisma.user.upsert({
    where: { username: 'vedeni' },
    update: { role: UserRole.vedeni, pinHash, mustChangePin: true },
    create: {
      username: 'vedeni',
      displayName: 'Vedení',
      pinHash,
      role: UserRole.vedeni,
      mustChangePin: true,
    },
  });

  await prisma.user.upsert({
    where: { username: 'ucetni' },
    update: { role: UserRole.ucetni, displayName: 'Administrativa', pinHash, mustChangePin: true },
    create: {
      username: 'ucetni',
      displayName: 'Administrativa',
      pinHash,
      role: UserRole.ucetni,
      mustChangePin: true,
    },
  });

  await prisma.user.upsert({
    where: { username: 'worker1' },
    update: { pinHash, mustChangePin: true },
    create: {
      username: 'worker1',
      displayName: 'Pracovník 1',
      pinHash,
      role: UserRole.worker,
      mustChangePin: true,
    },
  });

  await prisma.user.upsert({
    where: { username: 'worker2' },
    update: { pinHash, mustChangePin: true },
    create: {
      username: 'worker2',
      displayName: 'Pracovník 2',
      pinHash,
      role: UserRole.worker,
      mustChangePin: true,
    },
  });

  const job = await prisma.job.upsert({
    where: { projectNumber: '12345678' },
    update: {
      deletedAt: null,
      deletedById: null,
      deleteReason: null,
      isArchived: false,
      status: 'active' as const,
      name: 'Testovací stavba',
    },
    create: {
      projectNumber: '12345678',
      name: 'Testovací stavba',
      address: 'Praha 1',
      createdById: vedeni.id,
    },
  });

  const floor1 = await prisma.jobFloor.upsert({
    where: { id: '00000000-0000-0000-0000-000000000001' },
    update: {
      deletedAt: null,
      deletedById: null,
      deleteReason: null,
      name: '1. NP',
      jobId: job.id,
    },
    create: {
      id: '00000000-0000-0000-0000-000000000001',
      jobId: job.id,
      name: '1. NP',
      sortOrder: 1,
    },
  });

  const floor2 = await prisma.jobFloor.upsert({
    where: { id: '00000000-0000-0000-0000-000000000002' },
    update: {
      deletedAt: null,
      deletedById: null,
      deleteReason: null,
      name: '2. NP',
      jobId: job.id,
    },
    create: {
      id: '00000000-0000-0000-0000-000000000002',
      jobId: job.id,
      name: '2. NP',
      sortOrder: 2,
    },
  });

  console.log('Seed OK:', { admin: admin.username, job: job.projectNumber, floors: [floor1.name, floor2.name] });

  const worker1 = await prisma.user.findUnique({ where: { username: 'worker1' } });
  const worker2 = await prisma.user.findUnique({ where: { username: 'worker2' } });
  if (worker1) {
    await prisma.jobParticipant.upsert({
      where: { jobId_userId: { jobId: job.id, userId: worker1.id } },
      create: { jobId: job.id, userId: worker1.id, roleOnJob: 'worker', assignedById: vedeni.id },
      update: { roleOnJob: 'worker', lastActivityAt: new Date() },
    });
  }
  if (worker2) {
    await prisma.jobParticipant.upsert({
      where: { jobId_userId: { jobId: job.id, userId: worker2.id } },
      create: { jobId: job.id, userId: worker2.id, roleOnJob: 'worker', assignedById: vedeni.id },
      update: { roleOnJob: 'worker', lastActivityAt: new Date() },
    });
  }

  await seedDefaultPriceList();
  console.log('Price list seeded');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
