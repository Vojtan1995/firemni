import { Prisma, UserRole } from '@prisma/client';
import { validateSealForChecked } from '../services/seal-validation.service.js';

export const SEAL_PROBLEM_FILTERS = [
  'no_photo',
  'one_photo',
  'awaiting_review',
  'returned',
  'has_note',
  'missing_data',
] as const;

export type SealProblemFilter = (typeof SEAL_PROBLEM_FILTERS)[number];

export function parseSealFilters(raw?: string | string[]): SealProblemFilter[] {
  const parts = Array.isArray(raw)
    ? raw.flatMap((v) => v.split(','))
    : (raw ?? '').split(',');
  const allowed = new Set<string>(SEAL_PROBLEM_FILTERS);
  return parts
    .map((p) => p.trim())
    .filter((p): p is SealProblemFilter => allowed.has(p));
}

export function buildSealFilterWhere(
  filters: SealProblemFilter[],
  role: UserRole,
): Prisma.SealWhereInput {
  const and: Prisma.SealWhereInput[] = [];
  for (const f of filters) {
    switch (f) {
      case 'no_photo':
        and.push({ photos: { none: {} } });
        break;
      case 'awaiting_review':
        and.push({ status: 'draft' });
        break;
      case 'returned':
        and.push({ reviewStatus: 'returned' });
        break;
      case 'has_note':
        if (role === UserRole.worker) {
          and.push({ internalNote: { not: null } });
        } else {
          and.push({
            OR: [
              { note: { not: null } },
              { internalNote: { not: null } },
            ],
          });
        }
        break;
      default:
        break;
    }
  }
  if (and.length === 0) return {};
  return { AND: and };
}

function rowPhotoCount(row: Record<string, unknown>): number {
  const count = row._count as { photos?: number } | undefined;
  return count?.photos ?? 0;
}

function rowValidationShape(row: Record<string, unknown>) {
  return {
    system: String(row.system ?? ''),
    construction: String(row.construction ?? ''),
    location: String(row.location ?? ''),
    fireRating: String(row.fireRating ?? ''),
    entries: (row.entries as Array<{
      entryType: string;
      dimension: string;
      quantity: unknown;
      materials: Array<{ material: string }>;
    }>) ?? [],
    photos: Array.from({ length: rowPhotoCount(row) }, (_, i) => ({ id: String(i) })),
  };
}

export function applyPostSealFilters<T>(rows: T[], filters: SealProblemFilter[]): T[] {
  if (filters.length === 0) return rows;
  const needsPost = filters.some((f) => f === 'one_photo' || f === 'missing_data');
  if (!needsPost) return rows;

  return rows.filter((row) => {
    const r = row as Record<string, unknown>;
    for (const f of filters) {
      if (f === 'one_photo' && rowPhotoCount(r) !== 1) return false;
      if (f === 'missing_data') {
        const issues = validateSealForChecked(rowValidationShape(r));
        if (issues.length === 0) return false;
      }
    }
    return true;
  });
}

export function needsEntryInclude(filters: SealProblemFilter[]): boolean {
  return filters.includes('missing_data');
}
