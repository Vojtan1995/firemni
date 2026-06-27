import { prisma } from '../src/lib/prisma.js';

async function main() {
  if (process.env.NODE_ENV === 'production' || process.env.ALLOW_LOAD_VERIFY !== '1') {
    throw new Error('Load verification requires NODE_ENV!=production and ALLOW_LOAD_VERIFY=1');
  }

  const jobs = await prisma.job.findMany({
    where: { projectNumber: { startsWith: '9' }, name: { startsWith: 'LOAD Job ' } },
    select: {
      id: true,
      projectNumber: true,
      _count: { select: { floors: true, seals: true, participants: true } },
    },
  });
  const duplicateNumbers = await prisma.$queryRaw<Array<{ count: bigint }>>`
    SELECT COUNT(*)::bigint AS count FROM (
      SELECT s.job_id, s.floor_id, s.seal_number
      FROM seals s
      JOIN jobs j ON j.id = s.job_id
      WHERE j.name LIKE 'LOAD Job %' AND s.deleted_at IS NULL
      GROUP BY s.job_id, s.floor_id, s.seal_number
      HAVING COUNT(*) > 1
    ) duplicates
  `;
  const orphanEntries = await prisma.$queryRaw<Array<{ count: bigint }>>`
    SELECT COUNT(*)::bigint AS count
    FROM seal_entries e
    LEFT JOIN seals s ON s.id = e.seal_id
    WHERE s.id IS NULL
  `;
  const unfinishedMutations = await prisma.syncMutation.count({
    where: {
      deviceId: { startsWith: 'k6-' },
      processedAt: null,
    },
  });

  const failures: string[] = [];
  if (jobs.length === 0) failures.push('no synthetic LOAD jobs found');
  if (Number(duplicateNumbers[0]?.count || 0) > 0) failures.push('duplicate active seal numbers');
  if (Number(orphanEntries[0]?.count || 0) > 0) failures.push('orphan seal entries');
  if (unfinishedMutations > 0) failures.push(`${unfinishedMutations} unfinished k6 mutations`);
  for (const job of jobs) {
    if (job._count.floors !== 2) failures.push(`${job.projectNumber}: expected 2 floors`);
    if (job._count.participants < 1) failures.push(`${job.projectNumber}: no participant`);
  }

  console.log(JSON.stringify({
    ok: failures.length === 0,
    jobs: jobs.length,
    seals: jobs.reduce((sum, job) => sum + job._count.seals, 0),
    duplicateSealNumbers: Number(duplicateNumbers[0]?.count || 0),
    orphanEntries: Number(orphanEntries[0]?.count || 0),
    unfinishedMutations,
    failures,
  }, null, 2));
  if (failures.length) process.exitCode = 1;
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
