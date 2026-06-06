import { z } from 'zod';

const optionalMm = z.number().int().positive().optional();

export const sealEntrySchema = z.object({
  entryType: z.string().min(1),
  dimension: z.string().min(1),
  quantity: z.number().positive(),
  insulation: z.string().min(1),
  materials: z.array(z.string().min(1)).min(1),
  itemLengthMm: optionalMm,
  itemWidthMm: optionalMm,
});

export const sealBodySchema = z.object({
  jobId: z.string().uuid(),
  floorId: z.string().uuid(),
  sealNumber: z.string().regex(/^\d+$/, 'Číslo ucpávky musí být číselné'),
  system: z.string(),
  construction: z.string(),
  location: z.string(),
  fireRating: z.string(),
  note: z.string().optional(),
  internalNote: z.string().optional(),
  openingLengthMm: optionalMm,
  openingWidthMm: optionalMm,
  entries: z.array(sealEntrySchema).min(1),
  baseVersion: z.number().int().optional(),
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
