/** Chybová hláška při přeodečtení (odečet > celková plocha prostupu). */
export const OVER_DEDUCTION_MESSAGE =
  'Odečtená plocha je větší než celková plocha prostupu.';

/** Obdélník: plocha z rozměrů v mm → m² */
export function areaFromMm(lengthMm: number, widthMm: number): number {
  return (lengthMm * widthMm) / 1_000_000;
}

/** Kruh: plocha z průměru v mm → m² */
export function circleAreaFromDiameterMm(diameterMm: number): number {
  const r = diameterMm / 2;
  return (Math.PI * r * r) / 1_000_000;
}

/** VZT: běžné metry z D a Š v mm */
export function vztLinearMeters(lengthMm: number, widthMm: number): number {
  return ((2 * lengthMm + 2 * widthMm) * 2) / 1000;
}

/**
 * Plocha procházející instalace v m² podle tvaru (Task 5):
 *  - obdélník: šířka × výška / 1e6
 *  - kruh: π × (Ø/2)² / 1e6
 *  - ruční: zadaná hodnota v m²
 */
export type Deduction =
  | { kind: 'rect'; widthMm: number; heightMm: number }
  | { kind: 'circle'; diameterMm: number }
  | { kind: 'manual'; areaM2: number };

export function deductionArea(d: Deduction): number {
  switch (d.kind) {
    case 'rect':
      return areaFromMm(d.widthMm, d.heightMm);
    case 'circle':
      return circleAreaFromDiameterMm(d.diameterMm);
    case 'manual':
      return Math.max(0, d.areaM2);
  }
}

/**
 * Čistá účtovaná plocha prostupu = celková plocha otvoru − součet ploch instalací.
 * Nikdy není záporná; pokud odečet přesáhne celkovou plochu, vrátí wasNegative=true.
 */
export function netOpeningArea(
  openingAreaM2: number,
  deductionAreasM2: number[],
): { netAreaM2: number; wasNegative: boolean } {
  const totalDeduction = deductionAreasM2.reduce((sum, a) => sum + a, 0);
  const raw = openingAreaM2 - totalDeduction;
  if (raw < 0) {
    return { netAreaM2: 0, wasNegative: true };
  }
  return { netAreaM2: raw, wasNegative: false };
}

export type SealOpening = {
  openingLengthMm: number | null;
  openingWidthMm: number | null;
};

export type EntryDimensions = {
  entryType: string;
  itemLengthMm: number | null;
  itemWidthMm: number | null;
  dimension?: string | null;
};

/** Vytáhne průměr (Ø) z textového rozměru typu "Ø50" nebo "Ø20-100" (průměr = průměr středu). */
function diameterFromDimension(dim: string | null | undefined): number | null {
  if (!dim) return null;
  const n = dim.replace(/\s+/g, '').toLowerCase();
  const range = n.match(/ø(\d+)-(\d+)/);
  if (range) return Math.round((parseInt(range[1], 10) + parseInt(range[2], 10)) / 2);
  const single = n.match(/ø(\d+)/);
  if (single) return parseInt(single[1], 10);
  return null;
}

export type ComputedEntryValues = {
  calculatedAreaM2: number | null;
  calculatedLinearMeters: number | null;
  calculatedNetAreaM2: number | null;
  billableQuantity: number;
  unit: 'kus' | 'm2' | 'mb';
  netAreaWasNegative: boolean;
};

function hasMmPair(length: number | null, width: number | null): length is number {
  return length != null && width != null && length > 0 && width > 0;
}

/**
 * Plochy procházejících instalací (exaktně, Task 5):
 *  - má-li instalace obdélníkové rozměry (item D×Š) → obdélník
 *  - jinak má-li v rozměru průměr Ø → kruh
 *  - ostatní (bez rozměru) se neodečítají
 */
export function sumDeductionAreas(entries: EntryDimensions[]): number[] {
  const areas: number[] = [];
  for (const e of entries) {
    if (hasMmPair(e.itemLengthMm, e.itemWidthMm)) {
      areas.push(areaFromMm(e.itemLengthMm!, e.itemWidthMm!));
      continue;
    }
    const d = diameterFromDimension(e.dimension);
    if (d != null && d > 0) {
      areas.push(circleAreaFromDiameterMm(d));
    }
  }
  return areas;
}

export function computeEntryValues(
  entry: EntryDimensions & { quantity: number },
  sealOpening: SealOpening,
  allEntries: EntryDimensions[],
  entryIndex: number,
): ComputedEntryValues {
  const defaultResult: ComputedEntryValues = {
    calculatedAreaM2: null,
    calculatedLinearMeters: null,
    calculatedNetAreaM2: null,
    billableQuantity: entry.quantity,
    unit: 'kus',
    netAreaWasNegative: false,
  };

  if (entry.entryType === 'VZT' && hasMmPair(entry.itemLengthMm, entry.itemWidthMm)) {
    const mb = vztLinearMeters(entry.itemLengthMm!, entry.itemWidthMm!);
    return {
      ...defaultResult,
      calculatedLinearMeters: mb,
      billableQuantity: mb,
      unit: 'mb',
    };
  }

  if (entry.entryType === 'PROSTUP') {
    let grossArea: number | null = null;

    if (hasMmPair(entry.itemLengthMm, entry.itemWidthMm)) {
      grossArea = areaFromMm(entry.itemLengthMm!, entry.itemWidthMm!);
    } else if (
      hasMmPair(sealOpening.openingLengthMm, sealOpening.openingWidthMm)
    ) {
      grossArea = areaFromMm(sealOpening.openingLengthMm!, sealOpening.openingWidthMm!);
    }

    if (grossArea == null) {
      return defaultResult;
    }

    const openingSet = hasMmPair(sealOpening.openingLengthMm, sealOpening.openingWidthMm);
    const openingArea = openingSet
      ? areaFromMm(sealOpening.openingLengthMm!, sealOpening.openingWidthMm!)
      : grossArea;

    const otherEntries = allEntries.filter((_, i) => i !== entryIndex);
    const deductions = sumDeductionAreas(otherEntries);

    let netAreaM2 = grossArea;
    let wasNegative = false;

    if (openingSet && deductions.length > 0) {
      const net = netOpeningArea(openingArea, deductions);
      netAreaM2 = net.netAreaM2;
      wasNegative = net.wasNegative;
    }

    return {
      calculatedAreaM2: grossArea,
      calculatedLinearMeters: null,
      calculatedNetAreaM2: openingSet && deductions.length > 0 ? netAreaM2 : null,
      billableQuantity: netAreaM2,
      unit: 'm2',
      netAreaWasNegative: wasNegative,
    };
  }

  return defaultResult;
}
