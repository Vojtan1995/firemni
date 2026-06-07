import { Decimal } from '@prisma/client/runtime/library';

/** Převod Prisma Decimal na number pro výpočty a export. */
export function toNumber(value: Decimal | number | string | null | undefined): number {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  return Number(value);
}

/** Násobení cen s přesností na 2 desetinná místa (bez float chyb). */
export function multiplyMoney(
  unitPrice: Decimal | number | string,
  quantity: number,
): number {
  return new Decimal(unitPrice.toString()).mul(quantity).toDecimalPlaces(2).toNumber();
}
