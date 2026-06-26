import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { Prisma, PriceList, PriceListItem, MaterialMode } from '@prisma/client';
import { v4 as uuidv4 } from 'uuid';
import { prisma } from '../lib/prisma.js';
import { badRequest, notFound } from '../lib/errors.js';
import { toNumber, multiplyMoney } from '../lib/decimal.js';
import { logActivity } from './audit.service.js';
import { computeEntryValues, OVER_DEDUCTION_MESSAGE } from './seal-calculations.js';

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
    const m2Item = items.find((i) => i.unit === 'm2');
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

/**
 * Vybere cenu položky podle statusu workera. Worker "bez materiálu" platí cenu
 * bez materiálu (dnešní platné ceny), "s materiálem" cenu s materiálem.
 * Fallback na druhý sloupec, pokud daná cena chybí (kompatibilita starých dat).
 */
export function selectItemUnitPrice(
  item: PriceListItem,
  materialMode: MaterialMode,
): Prisma.Decimal {
  if (materialMode === MaterialMode.without_material) {
    return item.priceWithoutMaterial ?? item.priceWithMaterial;
  }
  return item.priceWithMaterial ?? item.priceWithoutMaterial ?? new Prisma.Decimal(0);
}

export function buildPricingData(
  item: PriceListItem,
  priceList: PriceList,
  quantity: number,
  userId: string,
  unit: string,
  materialMode: MaterialMode,
): Prisma.SealEntryUpdateInput {
  const price = selectItemUnitPrice(item, materialMode);
  const unitPrice = Number(price);
  const totalPrice = multiplyMoney(price, quantity);
  return {
    unitPrice,
    totalPrice,
    unit,
    currency: 'CZK',
    priceListVersion: priceList.version,
    priceListItem: { connect: { id: item.id } },
    priceMode: materialMode,
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
    select: {
      openingLengthMm: true,
      openingWidthMm: true,
      createdBy: { select: { materialMode: true } },
    },
  });
  const sealOpening = {
    openingLengthMm: seal?.openingLengthMm ?? null,
    openingWidthMm: seal?.openingWidthMm ?? null,
  };
  // Cena se řídí statusem workera, který ucpávku vytvořil.
  const materialMode =
    seal?.createdBy?.materialMode ?? MaterialMode.without_material;

  const entries = await client.sealEntry.findMany({
    where: { sealId, deletedAt: null },
    orderBy: { sortOrder: 'asc' },
  });

  const dimInputs = entries.map((e) => ({
    entryType: e.entryType,
    itemLengthMm: e.itemLengthMm,
    itemWidthMm: e.itemWidthMm,
    dimension: e.dimension,
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

    if (computed.netAreaWasNegative) {
      throw badRequest(OVER_DEDUCTION_MESSAGE);
    }

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
            materialMode,
          ),
        }
      : { ...computedFields, ...clearPricingData(userId) };

    await client.sealEntry.update({ where: { id: entry.id }, data });
  }
}

export type PriceListItemInput = {
  id?: string;
  category: string;
  sizeLabel: string;
  unit: string;
  priceWithMaterial: number;
  priceWithoutMaterial?: number | null;
  active?: boolean;
  sortOrder?: number;
};

async function allocateVersionLabel(now: Date): Promise<string> {
  const base = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  const existing = await prisma.priceList.findUnique({ where: { version: base } });
  if (!existing) return base;
  const suffix = `${String(now.getDate()).padStart(2, '0')}-${String(now.getHours()).padStart(2, '0')}${String(now.getMinutes()).padStart(2, '0')}`;
  const withTime = `${base}-${suffix}`;
  const clash = await prisma.priceList.findUnique({ where: { version: withTime } });
  if (!clash) return withTime;
  return `${withTime}-${String(now.getSeconds()).padStart(2, '0')}`;
}

export async function listPriceListVersions() {
  const lists = await prisma.priceList.findMany({
    orderBy: [{ active: 'desc' }, { validFrom: 'desc' }],
    include: { _count: { select: { items: true } } },
  });
  return lists.map((list) => ({
    id: list.id,
    version: list.version,
    validFrom: list.validFrom,
    validTo: list.validTo,
    active: list.active,
    itemCount: list._count.items,
  }));
}

export async function getPriceListByVersion(version: string) {
  const list = await prisma.priceList.findUnique({
    where: { version },
    include: {
      items: { orderBy: { sortOrder: 'asc' } },
    },
  });
  if (!list) throw notFound('Verze ceníku nenalezena');
  return list;
}

export async function publishPriceListChanges(userId: string, items: PriceListItemInput[]) {
  if (!items.length) throw badRequest('Ceník musí obsahovat alespoň jednu položku');

  const active = await prisma.priceList.findFirst({
    where: { active: true },
    include: { items: { orderBy: { sortOrder: 'asc' } } },
  });
  if (!active) throw notFound('Aktivní ceník není k dispozici');

  const now = new Date();
  const newVersion = await allocateVersionLabel(now);

  const created = await prisma.$transaction(async (tx) => {
    await tx.priceList.update({
      where: { id: active.id },
      data: { active: false, validTo: now },
    });

    let sortOrder = 0;
    const itemCreates: Prisma.PriceListItemUncheckedCreateWithoutPriceListInput[] = items.map(
      (item) => {
        const order = item.sortOrder ?? sortOrder++;
        return {
          id: uuidv4(),
          category: item.category.trim(),
          sizeLabel: item.sizeLabel.trim(),
          unit: item.unit.trim() || 'kus',
          priceWithMaterial: item.priceWithMaterial,
          priceWithoutMaterial: item.priceWithoutMaterial ?? null,
          active: item.active !== false,
          sortOrder: order,
        };
      },
    );

    return tx.priceList.create({
      data: {
        version: newVersion,
        validFrom: now,
        active: true,
        items: { create: itemCreates },
      },
      include: {
        items: {
          where: { active: true },
          orderBy: { sortOrder: 'asc' },
        },
      },
    });
  });

  await logActivity(userId, 'price_list_publish', 'price_list', created.id, {
    previousVersion: active.version,
    newVersion: created.version,
    itemCount: created.items.length,
  });

  return created;
}

export async function seedDefaultPriceList(version = '2026-06') {
  const active = await getActivePriceList();
  if (active) return active;

  const data = loadDefaultPriceList();
  const existing = await prisma.priceList.findUnique({
    where: { version },
    include: { items: true },
  });
  if (existing) {
    await prisma.priceList.updateMany({ where: { active: true }, data: { active: false } });
    return prisma.priceList.update({
      where: { id: existing.id },
      data: { active: true },
      include: { items: true },
    });
  }

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
        // Default ceník reprezentuje ceny "bez materiálu"; cena s materiálem se doplní později.
        priceWithMaterial: 0,
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
