/**
 * Testovací data: stavba „Nová zbrojovka" + 5 pater + 10 pracovníků,
 * každý 25 ucpávek (celkem 250) s prostupy a oceněním.
 *
 * Vše je zřetelně označené (projectNumber 90000001, username zbroj01..10),
 * aby šlo později čistě smazat: `npx tsx scripts/seed-test-data.ts --clean`.
 *
 * Pracuje proti DATABASE_URL. Pro produkci:
 *   DATABASE_URL=<PROD> SEED_DEMO_PIN=123456 npx tsx scripts/seed-test-data.ts
 *
 * Použití:
 *   npx tsx scripts/seed-test-data.ts          # vytvoří data
 *   npx tsx scripts/seed-test-data.ts --clean  # smaže testovací data
 */
import { PrismaClient, UserRole, SealTrade, SealStatus } from '@prisma/client';
import bcrypt from 'bcrypt';
import { priceSealEntries } from '../src/services/pricing.service.js';

const prisma = new PrismaClient();

const PROJECT_NUMBER = '90000001';
const JOB_NAME = 'Nová zbrojovka';
const USERNAME_PREFIX = 'zbroj';
const WORKER_COUNT = 10;
const SEALS_PER_WORKER = 25;
const FLOOR_NAMES = ['1. NP', '2. NP', '3. NP', '4. NP', '5. NP'];

const trades: SealTrade[] = [
  SealTrade.elektrikari,
  SealTrade.vzduchari,
  SealTrade.vodari,
  SealTrade.topenari,
  SealTrade.plynari,
  SealTrade.ostatni,
];

// Systém → reprezentativní materiál (musí existovat alespoň 1 materiál na entry).
const systems: { name: string; material: string }[] = [
  { name: 'Intuseal', material: 'INTU FR' },
  { name: 'Dunamenti', material: 'Polylack F/K' },
  { name: 'Fischer', material: 'FiAM' },
  { name: 'Hilti', material: 'CFS B' },
  { name: 'Protecta', material: 'FR ACRYLIC' },
];

const constructions = ['Beton/Cihla', 'SDK/PUR'];
const fireRatings = ['60 min', '90 min', '120 min'];
// Vč. nových podkategorií šachty (B3).
const locations = [
  'Stěna',
  'Strop',
  'Podlaha',
  'Šachta – Podlaha',
  'Šachta – Strop',
  'Šachta – Stěna',
];

// Typy prostupů s rozměry odpovídajícími ceníku (kus, bez nutnosti otvoru).
const entryPresets: { entryType: string; dimensions: string[] }[] = [
  { entryType: 'EL.V.', dimensions: ['Ø30', 'Ø40', 'Ø50', '100/100', '150/100', '200/100'] },
  { entryType: 'PVC', dimensions: ['Ø50', 'Ø75', 'Ø90', 'Ø110'] },
  { entryType: 'VZT', dimensions: ['Ø125', 'Ø160', 'Ø200'] },
];

function pick<T>(arr: T[], i: number): T {
  return arr[i % arr.length];
}

async function clean() {
  const job = await prisma.job.findUnique({ where: { projectNumber: PROJECT_NUMBER } });
  if (job) {
    const seals = await prisma.seal.findMany({ where: { jobId: job.id }, select: { id: true } });
    const sealIds = seals.map((s) => s.id);
    if (sealIds.length) {
      await prisma.sealEntryMaterial.deleteMany({
        where: { entry: { sealId: { in: sealIds } } },
      });
      await prisma.sealEntry.deleteMany({ where: { sealId: { in: sealIds } } });
      await prisma.sealMarker.deleteMany({ where: { sealId: { in: sealIds } } });
      await prisma.seal.deleteMany({ where: { id: { in: sealIds } } });
    }
    await prisma.jobParticipant.deleteMany({ where: { jobId: job.id } });
    await prisma.jobFloor.deleteMany({ where: { jobId: job.id } });
    await prisma.job.delete({ where: { id: job.id } });
  }
  await prisma.user.deleteMany({ where: { username: { startsWith: USERNAME_PREFIX } } });
  console.log('Testovací data „Nová zbrojovka" smazána.');
}

async function main() {
  if (process.argv.includes('--clean')) {
    await clean();
    return;
  }

  const pin = process.env.SEED_DEMO_PIN ?? '123456';
  const pinHash = await bcrypt.hash(pin, 10);

  // Autor stavby = nějaký vedení/admin (fallback na prvního existujícího uživatele).
  const creator =
    (await prisma.user.findFirst({ where: { role: UserRole.vedeni } })) ??
    (await prisma.user.findFirst({ where: { role: UserRole.admin } })) ??
    (await prisma.user.findFirst());
  if (!creator) throw new Error('V DB není žádný uživatel pro createdById stavby.');

  // 10 pracovníků
  const workers = [];
  for (let i = 1; i <= WORKER_COUNT; i++) {
    const username = `${USERNAME_PREFIX}${String(i).padStart(2, '0')}`;
    const worker = await prisma.user.upsert({
      where: { username },
      update: { role: UserRole.worker, pinHash, isActive: true },
      create: {
        username,
        displayName: `Zbrojovka Pracovník ${String(i).padStart(2, '0')}`,
        pinHash,
        role: UserRole.worker,
        mustChangePin: false,
      },
    });
    workers.push(worker);
  }

  // Stavba
  const job = await prisma.job.upsert({
    where: { projectNumber: PROJECT_NUMBER },
    update: { deletedAt: null, isArchived: false, status: 'active', name: JOB_NAME },
    create: {
      projectNumber: PROJECT_NUMBER,
      name: JOB_NAME,
      address: 'Brno',
      createdById: creator.id,
    },
  });

  // 5 pater
  const floors = [];
  for (let i = 0; i < FLOOR_NAMES.length; i++) {
    const existing = await prisma.jobFloor.findFirst({
      where: { jobId: job.id, name: FLOOR_NAMES[i] },
    });
    const floor =
      existing ??
      (await prisma.jobFloor.create({
        data: { jobId: job.id, name: FLOOR_NAMES[i], sortOrder: i + 1 },
      }));
    floors.push(floor);
  }

  // Účast pracovníků na stavbě
  for (const w of workers) {
    await prisma.jobParticipant.upsert({
      where: { jobId_userId: { jobId: job.id, userId: w.id } },
      create: { jobId: job.id, userId: w.id, roleOnJob: 'worker', assignedById: creator.id },
      update: { lastActivityAt: new Date() },
    });
  }

  // Idempotence: pokud už stavba má ucpávky, nevytvářet znovu (kolize čísel).
  const existingSeals = await prisma.seal.count({ where: { jobId: job.id } });
  if (existingSeals > 0) {
    console.log(
      `Stavba „${JOB_NAME}" už má ${existingSeals} ucpávek — vytváření přeskočeno. ` +
        'Pro znovuvytvoření nejdřív spusť --clean.',
    );
    console.log(`Hotovo. PIN pracovníků: ${pin}`);
    return;
  }

  // Ucpávky: každý pracovník 25, rovnoměrně přes 5 pater; čísla unikátní na patro.
  const perFloorCounter = floors.map(() => 0);
  let created = 0;
  let counter = 0;
  for (const worker of workers) {
    for (let i = 0; i < SEALS_PER_WORKER; i++) {
      const floorIndex = i % floors.length;
      const floor = floors[floorIndex];
      perFloorCounter[floorIndex] += 1;
      const sealNumber = String(perFloorCounter[floorIndex]);

      const system = pick(systems, counter);
      const preset = pick(entryPresets, counter);
      const entriesCount = 1 + (counter % 2); // 1–2 prostupy
      counter += 1;

      const seal = await prisma.seal.create({
        data: {
          jobId: job.id,
          floorId: floor.id,
          sealNumber,
          trade: pick(trades, counter),
          system: system.name,
          construction: pick(constructions, counter),
          location: pick(locations, counter),
          fireRating: pick(fireRatings, counter),
          status: SealStatus.draft,
          createdById: worker.id,
          updatedById: worker.id,
          entries: {
            create: Array.from({ length: entriesCount }, (_, j) => ({
              entryType: preset.entryType,
              dimension: pick(preset.dimensions, counter + j),
              quantity: 1 + ((counter + j) % 4),
              insulation: 'žádná',
              sortOrder: j,
              materials: { create: [{ material: system.material, sortOrder: 0 }] },
            })),
          },
        },
      });

      try {
        await priceSealEntries(seal.id, worker.id);
      } catch (e) {
        // Ocenění není kritické pro draft — pokračuj.
        console.warn(`Ocenění ucpávky ${sealNumber} selhalo: ${(e as Error).message}`);
      }
      created += 1;
    }
  }

  console.log(
    `Hotovo: stavba „${JOB_NAME}" (${PROJECT_NUMBER}), ${floors.length} pater, ` +
      `${workers.length} pracovníků, ${created} ucpávek. PIN pracovníků: ${pin}`,
  );
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
