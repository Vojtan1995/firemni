import { PrismaClient, UserRole } from '@prisma/client';
import bcrypt from 'bcrypt';
import { seedDefaultPriceList } from '../src/services/pricing.service.js';

const prisma = new PrismaClient();

async function main() {
  const pinHash = await bcrypt.hash('1234', 10);

  const admin = await prisma.user.upsert({
    where: { username: 'admin' },
    update: {},
    create: {
      username: 'admin',
      displayName: 'Administrátor',
      pinHash,
      role: UserRole.admin,
    },
  });

  const vedeni = await prisma.user.upsert({
    where: { username: 'vedeni' },
    update: { role: UserRole.vedeni },
    create: {
      username: 'vedeni',
      displayName: 'Vedení',
      pinHash,
      role: UserRole.vedeni,
    },
  });

  await prisma.user.upsert({
    where: { username: 'ucetni' },
    update: { role: UserRole.ucetni, displayName: 'Administrativa' },
    create: {
      username: 'ucetni',
      displayName: 'Administrativa',
      pinHash,
      role: UserRole.ucetni,
    },
  });

  await prisma.user.upsert({
    where: { username: 'worker1' },
    update: {},
    create: {
      username: 'worker1',
      displayName: 'Pracovník 1',
      pinHash,
      role: UserRole.worker,
    },
  });

  await prisma.user.upsert({
    where: { username: 'worker2' },
    update: {},
    create: {
      username: 'worker2',
      displayName: 'Pracovník 2',
      pinHash,
      role: UserRole.worker,
    },
  });

  const job = await prisma.job.upsert({
    where: { projectNumber: '12345678' },
    update: {
      deletedAt: null,
      deletedById: null,
      deleteReason: null,
      isArchived: false,
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
  await seedDefaultPriceList();
  console.log('Price list seeded');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
