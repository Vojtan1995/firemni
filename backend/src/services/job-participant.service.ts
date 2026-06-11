import { JobStatus } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { notFound } from '../lib/errors.js';

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

export async function joinJobByNumber(jobId: string, userId: string) {
  return prisma.$transaction(async (tx) => {
    const activeJob = await tx.job.findFirst({
      where: {
        id: jobId,
        deletedAt: null,
        status: JobStatus.active,
      },
      select: { id: true },
    });
    if (!activeJob) throw notFound('Stavba není aktivní');

    const inserted = await tx.jobParticipant.createMany({
      data: {
        jobId,
        userId,
        roleOnJob: 'worker',
      },
      skipDuplicates: true,
    });

    if (inserted.count === 0) {
      await tx.jobParticipant.update({
        where: { jobId_userId: { jobId, userId } },
        data: {
          lastActivityAt: new Date(),
          roleOnJob: 'worker',
        },
      });
      return { created: false };
    }

    await tx.activityLog.create({
      data: {
        userId,
        action: 'join_by_number',
        entityType: 'job',
        entityId: jobId,
      },
    });
    return { created: true };
  });
}

export async function listAllActiveJobs() {
  return prisma.job.findMany({
    where: { deletedAt: null, status: JobStatus.active },
    include: {
      floors: { where: { deletedAt: null }, orderBy: { sortOrder: 'asc' } },
    },
    orderBy: { createdAt: 'desc' },
  });
}

export async function listMyJobs(userId: string) {
  const rows = await prisma.jobParticipant.findMany({
    where: { userId, job: { deletedAt: null, status: JobStatus.active } },
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
