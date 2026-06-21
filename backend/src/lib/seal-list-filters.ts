import { Prisma, UserRole } from '@prisma/client';
import { validateSealForChecked } from '../services/seal-validation.service.js';

export const SEAL_PROBLEM_FILTERS = [
  'no_photo',
  'one_photo',
  'awaiting_review',
  'returned',
  'has_note',
  'missing_data',
  // Task 6 – praktické filtry seznamu ucpávek.
  'mine', // jen ucpávky vytvořené přihlášeným uživatelem
  'status_draft',
  'status_checked',
  'status_invoiced',
  'attention', // „K řešení" = vrácené (returned) NEBO nedokončené (missing_data)
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
  userId?: string,
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
      case 'status_draft':
        and.push({ status: 'draft' });
        break;
      case 'status_checked':
        and.push({ status: 'checked' });
        break;
      case 'status_invoiced':
        and.push({ status: 'invoiced' });
        break;
      case 'mine':
        // Bez userId nelze filtr aplikovat – raději nic nefiltrovat, než filtrovat chybně.
        if (userId) and.push({ createdById: userId });
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
      // 'attention' a 'missing_data' se vyhodnocují post-query (viz applyPostSealFilters).
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

function hasMissingData(r: Record<string, unknown>): boolean {
  return validateSealForChecked(rowValidationShape(r)).length > 0;
}

export function applyPostSealFilters<T>(rows: T[], filters: SealProblemFilter[]): T[] {
  if (filters.length === 0) return rows;
  const needsPost = filters.some(
    (f) => f === 'one_photo' || f === 'missing_data' || f === 'attention',
  );
  if (!needsPost) return rows;

  return rows.filter((row) => {
    const r = row as Record<string, unknown>;
    for (const f of filters) {
      if (f === 'one_photo' && rowPhotoCount(r) !== 1) return false;
      if (f === 'missing_data' && !hasMissingData(r)) return false;
      // „K řešení": vrácené k opravě NEBO nedokončené (chybí data ke kontrole).
      if (f === 'attention' && r.reviewStatus !== 'returned' && !hasMissingData(r)) {
        return false;
      }
    }
    return true;
  });
}

export function needsEntryInclude(filters: SealProblemFilter[]): boolean {
  return filters.includes('missing_data') || filters.includes('attention');
}
