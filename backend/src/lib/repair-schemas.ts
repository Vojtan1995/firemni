import { z } from 'zod';
import { SealTrade } from '@prisma/client';
import {
  refineSealEntriesDimensions,
  refineSealOpeningDimensions,
} from './zod-helpers.js';
import { sealEntrySchema } from './seal-schemas.js';

const optionalMm = z.number().int().positive().optional();

export const REPAIR_NOTE_MAX_LENGTH = 4000;

// Technická pole opravy odpovídají poli ucpávky (sealBodyBaseSchema), ale bez
// jobId/floorId/sealNumber (ty se odvozují z původní ucpávky) a s POVINNOU
// poznámkou (oprava bez popisu, co bylo opraveno, nemá smysl).
export const repairBodySchema = z
  .object({
    sealId: z.string().uuid(),
    note: z.string().min(1, 'Poznámka je povinná').max(REPAIR_NOTE_MAX_LENGTH),
    trade: z.nativeEnum(SealTrade, {
      errorMap: () => ({ message: 'Řemeslo je povinné' }),
    }),
    system: z.string().min(1),
    construction: z.string().min(1),
    location: z.string().min(1),
    fireRating: z.string().min(1),
    openingLengthMm: optionalMm,
    openingWidthMm: optionalMm,
    entries: z.array(sealEntrySchema).min(1),
  })
  .superRefine((data, ctx) => {
    refineSealOpeningDimensions(data, ctx);
    refineSealEntriesDimensions(data.entries, ctx);
  });

export type RepairBody = z.infer<typeof repairBodySchema>;
