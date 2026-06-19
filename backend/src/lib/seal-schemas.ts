import { z } from 'zod';
import { SealTrade } from '@prisma/client';
import { SEAL_NOTE_MAX_LENGTH } from './seal-notes.js';
import {
  assertPairedMm,
  refineSealEntriesDimensions,
  refineSealOpeningDimensions,
} from './zod-helpers.js';

const optionalNote = z.string().max(SEAL_NOTE_MAX_LENGTH).optional();

const optionalMm = z.number().int().positive().optional();

export const ELECTRO_INSTALLATION_TYPES = ['Svazek', 'Husí krk', 'Žlab'] as const;
export const STEEL_ENTRY_TYPE = 'OCEL';
export const ELECTRO_ENTRY_TYPE = 'EL.V.';

export const sealEntrySchema = z
  .object({
    entryType: z.string().min(1),
    dimension: z.string().min(1),
    quantity: z.number().positive(),
    insulation: z.string().min(1),
    materials: z.array(z.string().min(1)).min(1),
    itemLengthMm: optionalMm,
    itemWidthMm: optionalMm,
    steelInsulated: z.boolean().nullish(),
    electroInstallationType: z.enum(ELECTRO_INSTALLATION_TYPES).nullish(),
  })
  .superRefine((entry, ctx) => {
    assertPairedMm(entry.itemLengthMm, entry.itemWidthMm, ctx, []);
    if (entry.entryType === STEEL_ENTRY_TYPE && entry.steelInsulated == null) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['steelInsulated'],
        message: 'U typu Ocel je nutné vyplnit pole Doizolováno (Ano/Ne)',
      });
    }
    if (entry.entryType === ELECTRO_ENTRY_TYPE && !entry.electroInstallationType) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['electroInstallationType'],
        message: 'U typu Elektro je nutné vybrat typ instalace (Svazek/Husí krk/Žlab)',
      });
    }
  });

export const sealBodyBaseSchema = z.object({
  jobId: z.string().uuid(),
  floorId: z.string().uuid(),
  sealNumber: z.string().regex(/^\d+$/, 'Číslo ucpávky musí být číselné'),
  trade: z.nativeEnum(SealTrade, {
    errorMap: () => ({ message: 'Řemeslo je povinné' }),
  }),
  system: z.string().min(1),
  construction: z.string().min(1),
  location: z.string().min(1),
  fireRating: z.string().min(1),
  note: optionalNote,
  internalNote: optionalNote,
  openingLengthMm: optionalMm,
  openingWidthMm: optionalMm,
  markerPlacementPending: z.boolean().optional(),
  entries: z.array(sealEntrySchema).min(1),
  baseVersion: z.number().int().optional(),
});

export const sealBodySchema = sealBodyBaseSchema.superRefine((data, ctx) => {
  refineSealOpeningDimensions(data, ctx);
  refineSealEntriesDimensions(data.entries, ctx);
});

// Sdílené patch-schéma pro úpravu ucpávky. Používá se v HTTP PATCH i v sync
// update, aby obě cesty vynucovaly stejná pravidla (regex čísla, enum trade,
// .min(1) na textových polích). `entries` je volitelné, ale je-li přítomné,
// musí mít aspoň jednu položku – jinak by `entries: []` smazalo všechny aktivní
// prostupy bez náhrady. ZodObject (před superRefine), aby ho šlo dál `.extend`/
// `.omit` pro specifika jednotlivých cest.
export const sealPatchObjectSchema = sealBodyBaseSchema.partial().extend({
  entries: z.array(sealEntrySchema).min(1).optional(),
});

export function refineSealPatch(
  data: z.infer<typeof sealPatchObjectSchema>,
  ctx: z.RefinementCtx,
) {
  if (data.openingLengthMm != null || data.openingWidthMm != null) {
    refineSealOpeningDimensions(
      { openingLengthMm: data.openingLengthMm, openingWidthMm: data.openingWidthMm },
      ctx,
    );
  }
  if (data.entries?.length) {
    refineSealEntriesDimensions(data.entries, ctx);
  }
}

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
    steelInsulated: e.steelInsulated ?? null,
    electroInstallationType: e.electroInstallationType ?? null,
    sortOrder,
    materials: {
      create: e.materials.map((m, j) => ({ material: m, sortOrder: j })),
    },
  };
}
