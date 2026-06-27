import bcrypt from 'bcrypt';
import { createHash } from 'node:crypto';
import { prisma } from '../src/lib/prisma.js';

const JOBS = Number(process.env.LOAD_JOBS || 100);
const SEALS_PER_FLOOR = Number(process.env.LOAD_SEALS_PER_FLOOR || 500);
const WORKERS = Number(process.env.LOAD_WORKERS || 50);

function stableUuid(value: string): string {
  const hex = createHash('sha256').update(`unifast-load:${value}`).digest('hex').slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20)}`;
}

async function main() {
  if (process.env.NODE_ENV === 'production' || process.env.ALLOW_LOAD_SEED !== '1') {
    throw new Error('Load seed is forbidden unless NODE_ENV!=production and ALLOW_LOAD_SEED=1');
  }
  if (JOBS > 100 || SEALS_PER_FLOOR > 500 || WORKERS > 100) {
    throw new Error('Load seed exceeds the reviewed safety ceiling');
  }

  const admin = await prisma.user.findFirst({ where: { role: 'admin', isActive: true } });
  if (!admin) throw new Error('Run the normal seed first; active admin is missing');
  const pinHash = await bcrypt.hash('654321', 10);

  await prisma.user.createMany({
    data: Array.from({ length: WORKERS }, (_, i) => ({
      id: stableUuid(`worker:${i + 1}`),
      username: `load_worker_${i + 1}`,
      displayName: `Load Worker ${i + 1}`,
      pinHash,
      role: 'worker' as const,
      isActive: true,
    })),
    skipDuplicates: true,
  });
  const workers = await prisma.user.findMany({
    where: { username: { startsWith: 'load_worker_' } },
    orderBy: { username: 'asc' },
    take: WORKERS,
  });

  for (let jobIndex = 0; jobIndex < JOBS; jobIndex++) {
    const projectNumber = String(90_000_000 + jobIndex);
    const job = await prisma.job.upsert({
      where: { projectNumber },
      update: { name: `LOAD Job ${jobIndex + 1}`, status: 'active', deletedAt: null },
      create: {
        id: stableUuid(`job:${jobIndex}`),
        projectNumber,
        name: `LOAD Job ${jobIndex + 1}`,
        address: 'Synthetic staging data',
        createdById: admin.id,
      },
    });
    const floorIds = [stableUuid(`floor:${jobIndex}:1`), stableUuid(`floor:${jobIndex}:2`)];
    for (let floorIndex = 0; floorIndex < floorIds.length; floorIndex++) {
      await prisma.jobFloor.upsert({
        where: { id: floorIds[floorIndex] },
        create: {
          id: floorIds[floorIndex],
          jobId: job.id,
          name: `${floorIndex + 1}. NP`,
          sortOrder: floorIndex,
        },
        update: { jobId: job.id, deletedAt: null, sortOrder: floorIndex },
      });
    }
    // Každý worker vidí jen svou část staveb. To zachovává realistickou autorizaci
    // a umožňuje worker_1/worker_2 použít jako izolované IDOR testovací identity.
    await prisma.jobParticipant.deleteMany({ where: { jobId: job.id } });
    const assignedWorkers = workers.filter((_, workerIndex) => workerIndex % JOBS === jobIndex % JOBS);
    const participants = assignedWorkers.length > 0
      ? assignedWorkers
      : [workers[jobIndex % workers.length]];
    await prisma.jobParticipant.createMany({
      data: participants.map((worker) => ({
        jobId: job.id,
        userId: worker.id,
        roleOnJob: 'worker',
        assignedById: admin.id,
      })),
      skipDuplicates: true,
    });

    for (let floorIndex = 0; floorIndex < floorIds.length; floorIndex++) {
      const floorId = floorIds[floorIndex];
      const sealRows = Array.from({ length: SEALS_PER_FLOOR }, (_, sealIndex) => {
        const id = stableUuid(`seal:${jobIndex}:${floorIndex}:${sealIndex}`);
        return {
          id,
          jobId: job.id,
          floorId,
          sealNumber: String(sealIndex + 1),
          trade: 'elektrikari' as const,
          system: 'LOAD synthetic system',
          construction: 'Synthetic wall',
          location: `Zone ${sealIndex % 20}`,
          fireRating: 'EI 60',
          status: sealIndex % 4 === 0 ? ('checked' as const) : ('draft' as const),
          createdById: participants[sealIndex % participants.length].id,
        };
      });
      await prisma.seal.createMany({ data: sealRows, skipDuplicates: true });
      const entryRows = sealRows.flatMap((seal, index) => [
        {
          id: stableUuid(`entry:${jobIndex}:${floorIndex}:${index}:1`),
          sealId: seal.id,
          entryType: 'Kabel',
          dimension: '50',
          quantity: 1,
          insulation: 'Minerální vlna',
          sortOrder: 0,
        },
        {
          id: stableUuid(`entry:${jobIndex}:${floorIndex}:${index}:2`),
          sealId: seal.id,
          entryType: 'Trubka',
          dimension: '100',
          quantity: 1,
          insulation: 'Ano',
          sortOrder: 1,
        },
      ]);
      for (let i = 0; i < entryRows.length; i += 1000) {
        await prisma.sealEntry.createMany({
          data: entryRows.slice(i, i + 1000),
          skipDuplicates: true,
        });
      }
    }
    console.log(`Seeded ${jobIndex + 1}/${JOBS} jobs`);
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
