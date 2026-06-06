import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { Prisma, PriceList, PriceListItem } from '@prisma/client';
import { v4 as uuidv4 } from 'uuid';
import { prisma } from '../lib/prisma.js';
import { toNumber } from '../lib/decimal.js';
import { computeEntryValues } from './seal-calculations.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadDefaultPriceList(): PriceListSeed {
  const candidates = [
    path.join(__dirname, '../data/price-list-default.json'),
    path.join(process.cwd(), 'src/data/price-list-default.json'),
    path.join(process.cwd(), 'dist/data/price-list-default.json'),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return JSON.parse(fs.readFileSync(candidate, 'utf8')) as PriceListSeed;
    }
  }
  throw new Error('price-list-default.json not found');
}

export type EntryPricingInput = {
  entryType: string;
  dimension: string;
  insulation: string;
  quantity: number;
  preferredUnit?: 'kus' | 'm2' | 'mb';
};

type PriceListSeedItem = {
  name: string;
  price: number;
  unit?: string;
};

type PriceListSeed = Record<string, PriceListSeedItem[]>;

export function resolvePriceCategory(
  entryType: string,
  insulation: string,
  dimension: string,
  preferredUnit?: string,
): string | null {
  if (entryType === 'EL.V.') return 'EL. V.';
  if (entryType === 'PVC') return 'PVC';
  if (entryType === 'VZT') return 'VZT';
  if (entryType === 'PROSTUP') {
    if (preferredUnit === 'm2' || /dilata/i.test(dimension)) return 'PROSTUPY';
    if (insulation === 'hořlavá') return 'OC HOŘ';
    return 'OC';
  }
  if (entryType === 'OCEL') return 'OC';
  return null;
}

function normalizeDimension(dim: string): string {
  return dim.replace(/\s+/g, '').replace(/×/g, 'x').toLowerCase();
}

function parseDiameter(dim: string): number | null {
  const n = normalizeDimension(dim);
  const range = n.match(/ø(\d+)-(\d+)/);
  if (range) return Math.round((parseInt(range[1], 10) + parseInt(range[2], 10)) / 2);
  const single = n.match(/ø(\d+)/);
  if (single) return parseInt(single[1], 10);
  return null;
}

export function matchesSizeLabel(sizeLabel: string, dimension: string, unit: string): boolean {
  const label = sizeLabel.trim();
  const dim = dimension.trim();

  if (unit === 'mb' && /mb/i.test(dim)) return true;
  if (/dilata/i.test(label) && /dilata/i.test(dim)) return true;

  const normLabel = normalizeDimension(label);
  const normDim = normalizeDimension(dim);
  if (normLabel === normDim) return true;

  const leMatch = label.match(/≤\s*Ø\s*(\d+)/i);
  if (leMatch) {
    const max = parseInt(leMatch[1], 10);
    const d = parseDiameter(dim);
    return d !== null && d <= max;
  }

  const rangeLabel = label.match(/Ø\s*(\d+)-(\d+)/i);
  if (rangeLabel) {
    if (normDim.includes(`${rangeLabel[1]}-${rangeLabel[2]}`)) return true;
    const d = parseDiameter(dim);
    if (d === null) return false;
    return d >= parseInt(rangeLabel[1], 10) && d <= parseInt(rangeLabel[2], 10);
  }

  const exactLabel = label.match(/Ø\s*(\d+)/i);
  if (exactLabel && !label.includes('-') && !label.includes('≤')) {
    const expected = parseInt(exactLabel[1], 10);
    const d = parseDiameter(dim);
    return d === expected || normDim === `ø${expected}`;
  }

  if (label.includes('/')) {
    const parts = label.split('/');
    if (parts.length === 2) {
      const a = parts[0].trim();
      const b = parts[1].trim();
      return normDim.includes(`${a}/${b}`) || normDim.includes(`${a}x${b}`);
    }
  }

  if (label.toLowerCase() === 'mb') return /mb/i.test(dim);
  return false;
}

export async function getActivePriceList() {
  return prisma.priceList.findFirst({
    where: { active: true },
    include: {
      items: {
        where: { active: true },
        orderBy: { sortOrder: 'asc' },
      },
    },
  });
}

export async function lookupPriceItem(
  input: EntryPricingInput,
  priceList?: Awaited<ReturnType<typeof getActivePriceList>>,
) {
  const category = resolvePriceCategory(
    input.entryType,
    input.insulation,
    input.dimension,
    input.preferredUnit,
  );
  if (!category) return null;

  const list = priceList ?? (await getActivePriceList());
  if (!list) return null;

  const items = list.items.filter((i) => i.category === category);

  if (input.preferredUnit === 'm2') {
    const m2Item =
      items.find((i) => i.unit === 'm2' && i.sizeLabel === 'Plocha') ??
      items.find((i) => i.unit === 'm2' && !/dilata/i.test(i.sizeLabel));
    if (m2Item) return { item: m2Item, priceList: list };
  }

  if (input.preferredUnit === 'mb') {
    const mbItem = items.find((i) => i.unit === 'mb');
    if (mbItem) return { item: mbItem, priceList: list };
  }

  for (const item of items) {
    if (matchesSizeLabel(item.sizeLabel, input.dimension, item.unit)) {
      return { item, priceList: list };
    }
  }
  return null;
}

export function buildPricingData(
  item: PriceListItem,
  priceList: PriceList,
  quantity: number,
  userId: string,
  unit: string,
): Prisma.SealEntryUpdateInput {
  const unitPrice = Number(item.priceWithMaterial);
  const totalPrice = Math.round(unitPrice * quantity * 100) / 100;
  return {
    unitPrice,
    totalPrice,
    unit,
    currency: 'CZK',
    priceListVersion: priceList.version,
    priceListItem: { connect: { id: item.id } },
    priceMode: 'with_material',
    pricedAt: new Date(),
    pricedByUserId: userId,
    priceSource: 'automatic',
  };
}

export function clearPricingData(userId: string): Prisma.SealEntryUpdateInput {
  return {
    unitPrice: null,
    totalPrice: null,
    currency: 'CZK',
    priceListVersion: null,
    priceListItem: { disconnect: true },
    priceMode: null,
    pricedAt: new Date(),
    pricedByUserId: userId,
    priceSource: null,
  };
}

type TxClient = Prisma.TransactionClient;

export async function priceSealEntries(
  sealId: string,
  userId: string,
  client: TxClient | typeof prisma = prisma,
) {
  const priceList = await getActivePriceList();
  const seal = await client.seal.findUnique({
    where: { id: sealId },
    select: { openingLengthMm: true, openingWidthMm: true },
  });
  const sealOpening = {
    openingLengthMm: seal?.openingLengthMm ?? null,
    openingWidthMm: seal?.openingWidthMm ?? null,
  };

  const entries = await client.sealEntry.findMany({
    where: { sealId, deletedAt: null },
    orderBy: { sortOrder: 'asc' },
  });

  const dimInputs = entries.map((e) => ({
    entryType: e.entryType,
    itemLengthMm: e.itemLengthMm,
    itemWidthMm: e.itemWidthMm,
  }));

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    const computed = computeEntryValues(
      {
        entryType: entry.entryType,
        itemLengthMm: entry.itemLengthMm,
        itemWidthMm: entry.itemWidthMm,
        quantity: toNumber(entry.quantity),
      },
      sealOpening,
      dimInputs,
      i,
    );

    const preferredUnit = computed.unit !== 'kus' ? computed.unit : undefined;
    const match = await lookupPriceItem(
      {
        entryType: entry.entryType,
        dimension: entry.dimension,
        insulation: entry.insulation,
        quantity: computed.billableQuantity,
        preferredUnit,
      },
      priceList,
    );

    const computedFields: Prisma.SealEntryUpdateInput = {
      quantity: computed.billableQuantity,
      unit: computed.unit,
      calculatedAreaM2: computed.calculatedAreaM2,
      calculatedLinearMeters: computed.calculatedLinearMeters,
      calculatedNetAreaM2: computed.calculatedNetAreaM2,
    };

    const data = match
      ? {
          ...computedFields,
          ...buildPricingData(
            match.item,
            match.priceList,
            computed.billableQuantity,
            userId,
            computed.unit,
          ),
        }
      : { ...computedFields, ...clearPricingData(userId) };

    await client.sealEntry.update({ where: { id: entry.id }, data });
  }
}

export async function seedDefaultPriceList(version = '2026-06') {
  const data = loadDefaultPriceList();
  const existing = await prisma.priceList.findUnique({
    where: { version },
    include: { items: true },
  });
  if (existing) return existing;

  await prisma.priceList.updateMany({ where: { active: true }, data: { active: false } });

  let sortOrder = 0;
  const itemCreates: Prisma.PriceListItemUncheckedCreateWithoutPriceListInput[] = [];
  for (const [category, rows] of Object.entries(data)) {
    for (const row of rows) {
      itemCreates.push({
        id: uuidv4(),
        category,
        sizeLabel: row.name,
        unit: row.unit ?? 'kus',
        priceWithMaterial: row.price,
        priceWithoutMaterial: row.price,
        sortOrder: sortOrder++,
        active: true,
      });
    }
  }

  return prisma.priceList.create({
    data: {
      version,
      validFrom: new Date('2026-06-01'),
      active: true,
      items: { create: itemCreates },
    },
    include: { items: true },
  });
}

export async function assertSealEntriesPriced(sealId: string) {
  const unpriced = await prisma.sealEntry.count({
    where: {
      sealId,
      deletedAt: null,
      OR: [{ unitPrice: null }, { totalPrice: null }],
    },
  });
  return unpriced === 0;
}

export type { PriceList, PriceListItem };
