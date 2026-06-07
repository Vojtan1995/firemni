import { prisma } from '../lib/prisma.js';

export { getParticipantJobIds, isJobParticipant } from './authorization.service.js';

export async function touchJobParticipant(
  jobId: string,
  userId: string,
  roleOnJob: string,
  assignedById?: string,
) {
  await prisma.jobParticipant.upsert({
    where: { jobId_userId: { jobId, userId } },
    create: {
      jobId,
      userId,
      roleOnJob,
      assignedById: assignedById ?? null,
    },
    update: {
      lastActivityAt: new Date(),
      roleOnJob,
    },
  });
}

export async function listMyJobs(userId: string) {
  const rows = await prisma.jobParticipant.findMany({
    where: { userId, job: { deletedAt: null, isArchived: false } },
    include: {
      job: {
        include: {
          floors: { where: { deletedAt: null }, orderBy: { sortOrder: 'asc' } },
        },
      },
    },
    orderBy: { lastActivityAt: 'desc' },
  });
  return rows.map((r) => ({
    ...r.job,
    roleOnJob: r.roleOnJob,
    lastActivityAt: r.lastActivityAt,
  }));
}
