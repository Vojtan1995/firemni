/** Plocha z rozměrů v mm → m² */
export function areaFromMm(lengthMm: number, widthMm: number): number {
  return (lengthMm * widthMm) / 1_000_000;
}

/** VZT: běžné metry z D a Š v mm */
export function vztLinearMeters(lengthMm: number, widthMm: number): number {
  return ((2 * lengthMm + 2 * widthMm) * 2) / 1000;
}

/** Plocha prvku s příplatkem +50 mm na každou stranu */
export function elementAreaWithMargin(lengthMm: number, widthMm: number): number {
  return ((lengthMm + 50) * (widthMm + 50)) / 1_000_000;
}

/** Čistá plocha prostupu po odečtu prvků; nikdy záporná */
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
};

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

/** Součet ploch prvků s +50 mm (VZT a další s item rozměry). */
export function sumDeductionAreas(entries: EntryDimensions[]): number[] {
  return entries
    .filter((e) => hasMmPair(e.itemLengthMm, e.itemWidthMm))
    .map((e) => elementAreaWithMargin(e.itemLengthMm!, e.itemWidthMm!));
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
