/**
 * Překlad syrových audit záznamů (ActivityLog / ChangeLog) na lidsky čitelné české věty
 * a odkaz na entitu, na kterou se dá v UI prokliknout. Sdíleno endpointy v logs.routes.ts.
 */

export type LogEntityType =
  | 'seal'
  | 'job'
  | 'job_floor'
  | 'worksheet'
  | 'user'
  | 'price_list';

export type EntityRef = { type: LogEntityType; id: string };

export type ActivityLike = {
  action: string;
  entityType: string | null;
  entityId: string | null;
  metadata: unknown;
};

export type ChangeLike = {
  entityType: string;
  entityId: string;
  fieldName: string | null;
  oldValue: string | null;
  newValue: string | null;
};

/** Akce, které mění data (patří do „Historie změn"), nikoliv jen přihlášení/odhlášení. */
const NON_MUTATION_ACTIONS = new Set(['login', 'logout', 'change_pin']);

export function isDataMutation(action: string): boolean {
  return !NON_MUTATION_ACTIONS.has(action);
}

function refFor(entityType: string | null, entityId: string | null): EntityRef | null {
  if (!entityType || !entityId) return null;
  return { type: entityType as LogEntityType, id: entityId };
}

export function describeActivity(log: ActivityLike): { title: string; entity: EntityRef | null } {
  const meta = (log.metadata ?? {}) as Record<string, unknown>;
  const entity = refFor(log.entityType, log.entityId);

  switch (`${log.entityType}:${log.action}`) {
    case 'seal:create':
      return { title: 'Vytvořil novou ucpávku', entity };
    case 'seal:update':
      return { title: 'Upravil ucpávku', entity };
    case 'seal:status_change':
      return { title: `Změnil stav ucpávky (${meta.from ?? '?'} → ${meta.to ?? '?'})`, entity };
    case 'seal:override_locked_edit':
      return { title: `Upravil zamčenou ucpávku (důvod: ${meta.reason ?? '—'})`, entity };
    case 'seal:bulk_move':
      return { title: 'Přesunul ucpávku na jiné patro', entity };
    case 'seal:soft_delete':
      return { title: 'Smazal ucpávku', entity };
    case 'seal:restore':
      return { title: 'Obnovil ucpávku z koše', entity };
    case 'seal:photo_upload':
      return { title: 'Přidal fotku k ucpávce', entity };
    case 'seal:seal_marker_upsert':
      return { title: 'Umístil/přesunul značku na výkresu', entity };
    case 'seal:seal_marker_delete':
      return { title: 'Odstranil značku z výkresu', entity };

    case 'job:create':
      return { title: 'Vytvořil zakázku', entity };
    case 'job:update':
      return { title: 'Upravil zakázku', entity };
    case 'job:archive':
      return { title: 'Archivoval zakázku', entity };
    case 'job:unarchive':
      return { title: 'Obnovil zakázku z archivu', entity };
    case 'job:complete':
      return { title: 'Označil zakázku jako dokončenou', entity };
    case 'job:activate':
      return { title: 'Aktivoval zakázku', entity };
    case 'job:soft_delete':
      return { title: 'Smazal zakázku', entity };

    case 'job_floor:create':
      return { title: 'Vytvořil patro', entity };
    case 'job_floor:update':
      return { title: 'Upravil patro', entity };
    case 'job_floor:soft_delete':
      return { title: 'Smazal patro', entity };
    case 'job_floor:floor_drawing_upload':
      return { title: 'Nahrál výkres patra', entity };
    case 'job_floor:floor_drawing_delete':
      return { title: 'Smazal výkres patra', entity };

    case 'worksheet:worksheet_create':
      return { title: 'Vytvořil soupis práce', entity };
    case 'worksheet:worksheet_add_items':
      return { title: `Přidal položky do soupisu (${meta.count ?? '?'})`, entity };
    case 'worksheet:worksheet_status':
      return {
        title: `Změnil stav soupisu (${meta.from ?? '?'} → ${meta.to ?? '?'})${
          meta.comment ? ` – ${meta.comment}` : ''
        }`,
        entity,
      };

    case 'user:create':
      return { title: 'Vytvořil uživatele', entity };
    case 'user:update':
      return { title: 'Upravil uživatele', entity };
    case 'user:login':
      return { title: 'Přihlásil se', entity: null };
    case 'user:logout':
      return { title: 'Odhlásil se', entity: null };
    case 'user:change_pin':
      return { title: 'Změnil PIN', entity: null };

    case 'price_list:price_list_publish':
      return { title: `Zveřejnil nový ceník${meta.version ? ` (verze ${meta.version})` : ''}`, entity };

    default:
      return { title: `${log.action} (${log.entityType ?? '—'})`, entity };
  }
}

const CHANGE_FIELD_LABELS: Record<string, string> = {
  status: 'stav',
  floorId: 'patro',
  reviewStatus: 'stav revize',
  note: 'poznámka',
  internalNote: 'interní poznámka',
  sealNumber: 'číslo ucpávky',
  system: 'systém',
  construction: 'konstrukce',
  location: 'umístění',
  fireRating: 'požární odolnost',
  openingLengthMm: 'délka otvoru',
  openingWidthMm: 'šířka otvoru',
  markerPlacementPending: 'čeká na zakreslení',
  entries: 'prostupy',
};

export function describeChange(log: ChangeLike): { title: string; entity: EntityRef } {
  const field = CHANGE_FIELD_LABELS[log.fieldName ?? ''] ?? log.fieldName ?? 'pole';
  const entity = { type: log.entityType as LogEntityType, id: log.entityId };

  if (log.entityType === 'worksheet' && log.fieldName === 'status') {
    return { title: `Stav soupisu: ${log.oldValue ?? '—'} → ${log.newValue ?? '—'}`, entity };
  }
  if (log.fieldName === 'entries') {
    return { title: 'Upravil prostupy ucpávky', entity };
  }
  return {
    title: `Změna pole „${field}": ${log.oldValue ?? '—'} → ${log.newValue ?? '—'}`,
    entity,
  };
}
