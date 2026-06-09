import { UserRole } from '@prisma/client';

export const SEAL_NOTE_MAX_LENGTH = 4000;

export type SealNoteFields = {
  note: string | null;
  internalNote: string | null;
};

export type SealNotePatch = {
  note?: string | null;
  internalNote?: string | null;
};

/** Normalize empty strings to null. */
export function normalizeSealNote(value: string | null | undefined): string | null {
  if (value == null) return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

/** Resolve note fields for create — worker may only set internalNote. */
export function resolveSealNotesForCreate(
  role: UserRole,
  patch: SealNotePatch,
): SealNoteFields {
  const internalNote = normalizeSealNote(patch.internalNote);
  switch (role) {
    case UserRole.worker:
      return { note: null, internalNote };
    case UserRole.ucetni:
      return { note: normalizeSealNote(patch.note), internalNote: null };
    case UserRole.vedeni:
    case UserRole.admin:
      return {
        note: normalizeSealNote(patch.note),
        internalNote,
      };
    default:
      return { note: null, internalNote: null };
  }
}

/**
 * Apply note patch by role on update.
 * Disallowed fields are kept from existing (sync-safe ignore).
 */
export function applySealNotePatchByRole(
  role: UserRole,
  existing: SealNoteFields,
  patch: SealNotePatch,
): SealNoteFields {
  let note = existing.note;
  let internalNote = existing.internalNote;

  switch (role) {
    case UserRole.worker:
      if (patch.internalNote !== undefined) {
        internalNote = normalizeSealNote(patch.internalNote);
      }
      break;
    case UserRole.ucetni:
      if (patch.note !== undefined) {
        note = normalizeSealNote(patch.note);
      }
      break;
    case UserRole.vedeni:
    case UserRole.admin:
      if (patch.note !== undefined) {
        note = normalizeSealNote(patch.note);
      }
      if (patch.internalNote !== undefined) {
        internalNote = normalizeSealNote(patch.internalNote);
      }
      break;
    default:
      break;
  }

  return { note, internalNote };
}

/** Whether viewer role may see public note in API responses. */
export function canViewPublicSealNote(role: UserRole): boolean {
  return role !== UserRole.worker;
}

/** Whether viewer role may see internal note in API responses. */
export function canViewInternalSealNote(role: UserRole): boolean {
  return (
    role === UserRole.worker ||
    role === UserRole.vedeni ||
    role === UserRole.admin ||
    role === UserRole.ucetni
  );
}

/** Strip note fields from seal JSON for role (detail/list responses). */
export function filterSealNotesForViewer<T extends SealNoteFields>(
  role: UserRole,
  seal: T,
): T {
  return {
    ...seal,
    note: canViewPublicSealNote(role) ? seal.note : null,
    internalNote: canViewInternalSealNote(role) ? seal.internalNote : null,
  };
}
