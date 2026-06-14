import { z } from 'zod';
import { badRequest } from './errors.js';

/** Datum ve formátu YYYY-MM-DD (query parametry reportů). */
export const isoDateQuery = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Datum musí být ve formátu YYYY-MM-DD')
  .refine((value) => !Number.isNaN(Date.parse(`${value}T00:00:00.000Z`)), {
    message: 'Neplatné datum',
  });

export function parseIsoDateQuery(value: unknown): Date | undefined {
  if (value == null || value === '') return undefined;
  const parsed = isoDateQuery.safeParse(String(value));
  if (!parsed.success) {
    throw badRequest(parsed.error.errors[0]?.message ?? 'Neplatné datum');
  }
  return new Date(`${parsed.data}T00:00:00.000Z`);
}

export function parseIsoDateQueryEnd(value: unknown): Date | undefined {
  if (value == null || value === '') return undefined;
  const parsed = isoDateQuery.safeParse(String(value));
  if (!parsed.success) {
    throw badRequest(parsed.error.errors[0]?.message ?? 'Neplatné datum');
  }
  return new Date(`${parsed.data}T23:59:59.999Z`);
}

/**
 * Parsuje plný ISO timestamp (např. `since` u logů, inkrementální sync).
 * Na rozdíl od `parseIsoDateQuery` přijímá i čas; nevalidní vstup → 400.
 */
export function parseIsoDateTimeQuery(value: unknown): Date | undefined {
  if (value == null || value === '') return undefined;
  const parsed = new Date(String(value));
  if (Number.isNaN(parsed.getTime())) {
    throw badRequest('Neplatné datum');
  }
  return parsed;
}

export function assertPairedMm(
  length: number | undefined,
  width: number | undefined,
  ctx: z.RefinementCtx,
  path: (string | number)[],
) {
  const hasLength = length != null;
  const hasWidth = width != null;
  if (hasLength !== hasWidth) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'Délka a šířka musí být zadány společně',
      path: hasLength ? [...path, 'itemWidthMm'] : [...path, 'itemLengthMm'],
    });
  }
}

export function refineSealOpeningDimensions(
  data: { openingLengthMm?: number; openingWidthMm?: number },
  ctx: z.RefinementCtx,
) {
  const hasLength = data.openingLengthMm != null;
  const hasWidth = data.openingWidthMm != null;
  if (hasLength !== hasWidth) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'Rozměry otvoru musí být zadány společně',
      path: hasLength ? ['openingWidthMm'] : ['openingLengthMm'],
    });
  }
}

export function refineSealEntriesDimensions(
  entries: { itemLengthMm?: number; itemWidthMm?: number }[],
  ctx: z.RefinementCtx,
) {
  entries.forEach((entry, index) => {
    assertPairedMm(entry.itemLengthMm, entry.itemWidthMm, ctx, ['entries', index]);
  });
}
