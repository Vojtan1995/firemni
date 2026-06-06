import { Decimal } from '@prisma/client/runtime/library';

/** Převod Prisma Decimal na number pro výpočty a export. */
export function toNumber(value: Decimal | number | string | null | undefined): number {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  return Number(value);
}
