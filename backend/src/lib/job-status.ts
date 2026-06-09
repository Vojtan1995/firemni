import { JobStatus, UserRole } from '@prisma/client';

export const JOB_STATUS_VALUES = ['active', 'completed', 'archived'] as const;

export function parseJobStatusQuery(
  status?: string,
  archived?: string,
): JobStatus | undefined {
  if (status && JOB_STATUS_VALUES.includes(status as (typeof JOB_STATUS_VALUES)[number])) {
    return status as JobStatus;
  }
  if (archived === 'true') return JobStatus.archived;
  if (archived === 'false') return JobStatus.active;
  return undefined;
}

/** Sloupce jobu při změně lifecycle stavu — drží sync s legacy `isArchived`. */
export function jobStatusPatch(status: JobStatus) {
  return {
    status,
    isArchived: status === JobStatus.archived,
  };
}

export function workerCanAccessJob(status: JobStatus): boolean {
  return status === JobStatus.active;
}

export function jobAllowsWrites(status: JobStatus): boolean {
  return status === JobStatus.active;
}

export function jobAccessDeniedMessage(status: JobStatus): string {
  if (status === JobStatus.archived) return 'Stavba je archivována';
  if (status === JobStatus.completed) return 'Stavba je dokončena';
  return 'Stavba není aktivní';
}

export function assertWorkerJobAccess(role: UserRole, status: JobStatus) {
  if (role === UserRole.worker && !workerCanAccessJob(status)) {
    return false;
  }
  return true;
}
