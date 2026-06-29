import { describe, expect, it } from '@jest/globals';
import { describeActivity } from '../dist/lib/log-labels.js';

describe('log labels', () => {
  it('includes job, floor and worksheet context in human-readable activity titles', () => {
    expect(
      describeActivity({
        action: 'create',
        entityType: 'job',
        entityId: 'job-1',
        metadata: { projectNumber: '24015', jobName: 'OC Alfa' },
      }).title,
    ).toContain('24015 OC Alfa');

    expect(
      describeActivity({
        action: 'create',
        entityType: 'job_floor',
        entityId: 'floor-1',
        metadata: { floorName: '2.NP', projectNumber: '24015', jobName: 'OC Alfa' },
      }).title,
    ).toContain('2.NP');

    expect(
      describeActivity({
        action: 'floor_drawing_upload',
        entityType: 'job_floor',
        entityId: 'floor-1',
        metadata: {
          floorName: '2.NP',
          projectNumber: '24015',
          jobName: 'OC Alfa',
          fileName: 'vykres.pdf',
        },
      }).title,
    ).toContain('vykres.pdf');

    expect(
      describeActivity({
        action: 'worksheet_create',
        entityType: 'worksheet',
        entityId: 'worksheet-1',
        metadata: {
          audience: 'customer',
          projectNumber: '24015',
          jobName: 'OC Alfa',
          workers: ['Jan Novák'],
        },
      }).title,
    ).toContain('Jan Novák');
  });
});
