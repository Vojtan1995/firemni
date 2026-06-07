import { UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';

function requiresJobParticipantCheck(role: UserRole): boolean {
  return role === UserRole.worker;
}

export function bypassesJobParticipantCheck(role: UserRole): boolean {
  return !requiresJobParticipantCheck(role);
}

export async function isJobParticipant(jobId: string, userId: string): Promise<boolean> {
  const row = await prisma.jobParticipant.findUnique({
    where: { jobId_userId: { jobId, userId } },
  });
  return row != null;
}

export async function getParticipantJobIds(userId: string): Promise<string[]> {
  const rows = await prisma.jobParticipant.findMany({
    where: { userId },
    select: { jobId: true },
  });
  return rows.map((r) => r.jobId);
}

export async function assertJobParticipant(jobId: string, userId: string) {
  if (!(await isJobParticipant(jobId, userId))) {
    throw forbidden('Nemáte přístup k této zakázce');
  }
}

export async function assertJobReadable(jobId: string, role: UserRole, userId: string) {
  const job = await prisma.job.findFirst({ where: { id: jobId, deletedAt: null } });
  if (!job) throw notFound('Stavba nenalezena');
  if (job.isArchived && role === UserRole.worker) {
    throw notFound('Stavba není aktivní');
  }
  if (!bypassesJobParticipantCheck(role)) {
    await assertJobParticipant(jobId, userId);
  }
  return job;
}

export async function assertJobWritable(jobId: string, role: UserRole, userId: string) {
  const job = await assertJobReadable(jobId, role, userId);
  if (job.isArchived) {
    throw forbidden('Stavba je archivována');
  }
  return job;
}

export async function assertFloorBelongsToJob(floorId: string, jobId: string) {
  const floor = await prisma.jobFloor.findFirst({
    where: { id: floorId, jobId, deletedAt: null },
  });
  if (!floor) throw badRequest('Patro nepatří k zadané zakázce');
  return floor;
}

export async function assertFloorReadable(floorId: string, role: UserRole, userId: string) {
  const floor = await prisma.jobFloor.findFirst({
    where: { id: floorId, deletedAt: null },
  });
  if (!floor) throw notFound('Patro nenalezeno');
  await assertJobReadable(floor.jobId, role, userId);
  return floor;
}

export async function assertSealReadable(sealId: string, role: UserRole, userId: string) {
  const seal = await prisma.seal.findFirst({
    where: { id: sealId, deletedAt: null },
    include: { job: true },
  });
  if (!seal) throw notFound('Ucpávka nenalezena');
  await assertJobReadable(seal.jobId, role, userId);
  return seal;
}

export function buildParticipantJobFilter(role: UserRole, participantJobIds: string[]) {
  if (bypassesJobParticipantCheck(role)) {
    return {};
  }
  if (participantJobIds.length === 0) {
    return { id: { in: [] as string[] } };
  }
  return { id: { in: participantJobIds } };
}

export { SYNC_PULL_BATCH_LIMIT } from '../lib/limits.js';
