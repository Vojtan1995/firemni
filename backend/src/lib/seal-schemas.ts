import { z } from 'zod';
import { SEAL_NOTE_MAX_LENGTH } from './seal-notes.js';
import {
  assertPairedMm,
  refineSealEntriesDimensions,
  refineSealOpeningDimensions,
} from './zod-helpers.js';

const optionalNote = z.string().max(SEAL_NOTE_MAX_LENGTH).optional();

const optionalMm = z.number().int().positive().optional();

export const sealEntrySchema = z
  .object({
    entryType: z.string().min(1),
    dimension: z.string().min(1),
    quantity: z.number().positive(),
    insulation: z.string().min(1),
    materials: z.array(z.string().min(1)).min(1),
    itemLengthMm: optionalMm,
    itemWidthMm: optionalMm,
  })
  .superRefine((entry, ctx) => {
    assertPairedMm(entry.itemLengthMm, entry.itemWidthMm, ctx, []);
  });

export const sealBodyBaseSchema = z.object({
  jobId: z.string().uuid(),
  floorId: z.string().uuid(),
  sealNumber: z.string().regex(/^\d+$/, 'Číslo ucpávky musí být číselné'),
  system: z.string().min(1),
  construction: z.string().min(1),
  location: z.string().min(1),
  fireRating: z.string().min(1),
  note: optionalNote,
  internalNote: optionalNote,
  openingLengthMm: optionalMm,
  openingWidthMm: optionalMm,
  entries: z.array(sealEntrySchema).min(1),
  baseVersion: z.number().int().optional(),
});

export const sealBodySchema = sealBodyBaseSchema.superRefine((data, ctx) => {
  refineSealOpeningDimensions(data, ctx);
  refineSealEntriesDimensions(data.entries, ctx);
});

export function entryCreateData(
  e: z.infer<typeof sealEntrySchema>,
  sortOrder: number,
) {
  return {
    entryType: e.entryType,
    dimension: e.dimension,
    quantity: e.quantity,
    insulation: e.insulation,
    itemLengthMm: e.itemLengthMm ?? null,
    itemWidthMm: e.itemWidthMm ?? null,
    sortOrder,
    materials: {
      create: e.materials.map((m, j) => ({ material: m, sortOrder: j })),
    },
  };
}
