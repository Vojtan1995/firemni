import { describe, it, expect } from '@jest/globals';
import { JobStatus } from '@prisma/client';
import {
  jobStatusPatch,
  parseJobStatusQuery,
  workerCanAccessJob,
  jobAllowsWrites,
} from '../dist/lib/job-status.js';

describe('job-status', () => {
  it('parses status and legacy archived query', () => {
    expect(parseJobStatusQuery('completed')).toBe(JobStatus.completed);
    expect(parseJobStatusQuery(undefined, 'true')).toBe(JobStatus.archived);
    expect(parseJobStatusQuery(undefined, 'false')).toBe(JobStatus.active);
  });

  it('syncs isArchived with status patch', () => {
    expect(jobStatusPatch(JobStatus.archived)).toEqual({
      status: JobStatus.archived,
      isArchived: true,
    });
    expect(jobStatusPatch(JobStatus.active)).toEqual({
      status: JobStatus.active,
      isArchived: false,
    });
  });

  it('worker only accesses active jobs', () => {
    expect(workerCanAccessJob(JobStatus.active)).toBe(true);
    expect(workerCanAccessJob(JobStatus.completed)).toBe(false);
    expect(jobAllowsWrites(JobStatus.completed)).toBe(false);
  });
});
