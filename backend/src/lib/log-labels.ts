/**
 * Překlad syrových audit záznamů (ActivityLog / ChangeLog) na lidsky čitelné české věty,
 * podkategorii pro skupinové zobrazení v UI a odkaz na entitu, na kterou se dá v UI
 * prokliknout. Sdíleno endpointy v logs.routes.ts.
 */

export type LogEntityType =
  | 'seal'
  | 'seal_repair'
  | 'seal_photo'
  | 'job'
  | 'job_floor'
  | 'worksheet'
  | 'user'
  | 'price_list';

export type EntityRef = { type: LogEntityType; id: string };

/** Podkategorie pro skupinové zobrazení logů v UI (česky, bez syrových názvů akcí). */
export type LogCategory =
  | 'Vytvořené'
  | 'Stav'
  | 'Úpravy'
  | 'Přesuny'
  | 'Fotky a výkresy'
  | 'Smazání a obnova'
  | 'Ceník'
  | 'Ostatní';

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

/**
 * Pole ChangeLogu, která jsou jen interní technické účetnictví (odvozené
 * příznaky), ne skutečná úprava, kterou udělal člověk — v „Historii změn" je
 * potlačíme, aby tam nebyl šum vedle smysluplných akcí (vytvoření, úprava,
 * stav, foto, výkres…). `markerPlacementPending` se přepočítá automaticky při
 * každém umístění značky / nahrání výkresu, takže by zaplevelovalo log
 * duplicitním záznamem ke každé takové akci, která už má svůj vlastní
 * ActivityLog popis.
 */
const NOISY_CHANGE_FIELDS = new Set(['markerPlacementPending']);

export function isNoiseChangeField(fieldName: string | null): boolean {
  return fieldName != null && NOISY_CHANGE_FIELDS.has(fieldName);
}

function refFor(entityType: string | null, entityId: string | null): EntityRef | null {
  if (!entityType || !entityId) return null;
  return { type: entityType as LogEntityType, id: entityId };
}

/** České hodnoty stavu ucpávky – pro zobrazení v titulcích logů (žádné syrové enum hodnoty). */
const SEAL_STATUS_LABELS: Record<string, string> = {
  draft: 'Rozpracovaná',
  checked: 'Zkontrolovaná',
  invoiced: 'Vyfakturovaná',
};

/** České hodnoty stavu soupisu – pro zobrazení v titulcích logů. */
const WORKSHEET_STATUS_LABELS: Record<string, string> = {
  draft: 'Rozpracovaný',
  submitted: 'Odevzdaný',
  reviewed: 'Schválený',
  ready_for_invoice: 'Připravený k fakturaci',
  invoiced: 'Vyfakturovaný',
  archived: 'Archivovaný',
};

function sealStatusCs(value: unknown): string {
  const s = String(value ?? '');
  return SEAL_STATUS_LABELS[s] ?? (s || '?');
}

function worksheetStatusCs(value: unknown): string {
  const s = String(value ?? '');
  return WORKSHEET_STATUS_LABELS[s] ?? (s || '?');
}

function clean(value: unknown): string {
  return String(value ?? '').trim();
}

function jobLabel(meta: Record<string, unknown>) {
  const number = clean(meta.projectNumber);
  const name = clean(meta.jobName);
  if (number && name) return `${number} ${name}`;
  return number || name || '';
}

function floorLabel(meta: Record<string, unknown>) {
  return clean(meta.floorName) || 'patra';
}

function inJob(meta: Record<string, unknown>) {
  const label = jobLabel(meta);
  return label ? ` ve stavbě ${label}` : '';
}

function worksheetAudienceCs(value: unknown) {
  return value === 'customer' ? 'pro zákazníka' : 'pro pracovníky';
}

function workersLabel(meta: Record<string, unknown>) {
  const workers = Array.isArray(meta.workers)
    ? meta.workers.map((w) => clean(w)).filter(Boolean)
    : [];
  return workers.length > 0 ? ` (${workers.join(', ')})` : '';
}

function periodLabel(meta: Record<string, unknown>) {
  const from = clean(meta.periodFrom).split('T')[0];
  const to = clean(meta.periodTo).split('T')[0];
  if (!from && !to) return '';
  return ` za období ${from || '—'} až ${to || '—'}`;
}

/** Podkategorie pro ActivityLog akci – podle entityType:action. */
function categoryForActivity(entityType: string | null, action: string): LogCategory {
  if (action === 'create' || action === 'worksheet_create' || action === 'worksheet_add_items') {
    return 'Vytvořené';
  }
  if (action === 'status_change' || action === 'worksheet_status') return 'Stav';
  if (action === 'bulk_move') return 'Přesuny';
  if (
    action === 'photo_upload' ||
    action === 'photo_delete' ||
    action === 'seal_marker_upsert' ||
    action === 'seal_marker_delete' ||
    action === 'floor_drawing_upload' ||
    action === 'floor_drawing_delete'
  ) {
    return 'Fotky a výkresy';
  }
  if (action === 'soft_delete' || action === 'restore') return 'Smazání a obnova';
  if (entityType === 'price_list') return 'Ceník';
  if (action === 'update' || action === 'override_locked_edit') return 'Úpravy';
  return 'Ostatní';
}

export function describeActivity(
  log: ActivityLike,
): { title: string; entity: EntityRef | null; category: LogCategory } {
  const meta = (log.metadata ?? {}) as Record<string, unknown>;
  const entity = refFor(log.entityType, log.entityId);
  const category = categoryForActivity(log.entityType, log.action);

  switch (`${log.entityType}:${log.action}`) {
    case 'job:create':
      return { title: `Vytvořil stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category };
    case 'job:update':
      return { title: `Upravil stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category };
    case 'job:archive':
      return { title: `Archivoval stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category: 'Smazání a obnova' };
    case 'job:unarchive':
      return { title: `Obnovil stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''} z archivu`, entity, category: 'Smazání a obnova' };
    case 'job:complete':
      return { title: `Označil stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''} jako dokončenou`, entity, category: 'Stav' };
    case 'job:activate':
      return { title: `Aktivoval stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category: 'Stav' };
    case 'job:soft_delete':
      return { title: `Smazal stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category: 'Smazání a obnova' };

    case 'job_floor:create':
      return { title: `Vytvořil patro ${floorLabel(meta)}${inJob(meta)}`, entity, category };
    case 'job_floor:update':
      return { title: `Upravil patro ${floorLabel(meta)}${inJob(meta)}`, entity, category };
    case 'job_floor:soft_delete':
      return { title: `Smazal patro ${floorLabel(meta)}${inJob(meta)}`, entity, category };
    case 'job_floor:floor_drawing_upload':
      return {
        title: `${meta.replaced ? 'Nahradil' : 'Nahrál'} výkres patra ${floorLabel(meta)}${inJob(meta)}${
          meta.fileName ? ` (${meta.fileName})` : ''
        }`,
        entity,
        category,
      };
    case 'job_floor:floor_drawing_delete':
      return { title: `Smazal výkres patra ${floorLabel(meta)}${inJob(meta)}`, entity, category };

    case 'worksheet:worksheet_create':
      return {
        title: `Vytvořil soupis ${worksheetAudienceCs(meta.audience)}${inJob(meta)}${workersLabel(meta)}${periodLabel(meta)}`,
        entity,
        category,
      };
    case 'worksheet:worksheet_add_items':
      return {
        title: `Přidal položky do soupisu${inJob(meta)} (${meta.count ?? '?'})`,
        entity,
        category,
      };
    case 'worksheet:worksheet_status':
      return {
        title: `Změnil stav soupisu ${worksheetAudienceCs(meta.audience)}${inJob(meta)}${workersLabel(meta)}: ${worksheetStatusCs(meta.from)} → ${worksheetStatusCs(meta.to)}${
          meta.comment ? ` – ${meta.comment}` : ''
        }`,
        entity,
        category,
      };
    case 'worksheet:worksheet_delete':
      return {
        title: `Smazal rozpracovaný soupis ${worksheetAudienceCs(meta.audience)}${inJob(meta)}${workersLabel(meta)}${periodLabel(meta)}`,
        entity,
        category,
      };
    case 'seal:create':
      return { title: 'Vytvořil novou ucpávku', entity, category };
    case 'seal:update':
      return { title: 'Upravil ucpávku', entity, category };
    case 'seal:status_change':
      return {
        title: `Změnil stav ucpávky (${sealStatusCs(meta.from)} → ${sealStatusCs(meta.to)})`,
        entity,
        category,
      };
    case 'seal:override_locked_edit':
      return { title: `Upravil zamčenou ucpávku (důvod: ${meta.reason ?? '—'})`, entity, category };
    case 'seal:bulk_move':
      return { title: 'Přesunul ucpávku na jiné patro', entity, category };
    case 'seal:soft_delete':
      return { title: 'Smazal ucpávku', entity, category };
    case 'seal:restore':
      return { title: 'Obnovil ucpávku z koše', entity, category };
    case 'seal:photo_upload':
      return { title: 'Přidal fotku k ucpávce', entity, category };
    case 'seal:seal_marker_upsert':
      return { title: 'Umístil/přesunul značku na výkresu', entity, category };
    case 'seal:seal_marker_delete':
      return { title: 'Odstranil značku z výkresu', entity, category };

    case 'seal_repair:create':
      return { title: 'Vytvořil opravu ucpávky', entity, category };

    case 'seal_photo:photo_delete':
      return {
        title: 'Smazal fotku ucpávky',
        entity: meta.sealId ? { type: 'seal', id: String(meta.sealId) } : null,
        category,
      };

    case 'job:create':
      return { title: 'Vytvořil zakázku', entity, category };
    case 'job:update':
      return { title: 'Upravil zakázku', entity, category };
    case 'job:archive':
      return { title: 'Archivoval zakázku', entity, category: 'Smazání a obnova' };
    case 'job:unarchive':
      return { title: 'Obnovil zakázku z archivu', entity, category: 'Smazání a obnova' };
    case 'job:complete':
      return { title: 'Označil zakázku jako dokončenou', entity, category: 'Stav' };
    case 'job:activate':
      return { title: 'Aktivoval zakázku', entity, category: 'Stav' };
    case 'job:soft_delete':
      return { title: 'Smazal zakázku', entity, category: 'Smazání a obnova' };

    case 'job_floor:create':
      return { title: 'Vytvořil patro', entity, category };
    case 'job_floor:update':
      return { title: 'Upravil patro', entity, category };
    case 'job_floor:soft_delete':
      return { title: 'Smazal patro', entity, category };
    case 'job_floor:floor_drawing_upload':
      return { title: 'Nahrál výkres patra', entity, category };
    case 'job_floor:floor_drawing_delete':
      return { title: 'Smazal výkres patra', entity, category };

    case 'worksheet:worksheet_create':
      return { title: 'Vytvořil soupis práce', entity, category };
    case 'worksheet:worksheet_add_items':
      return { title: `Přidal položky do soupisu (${meta.count ?? '?'})`, entity, category };
    case 'worksheet:worksheet_status':
      return {
        title: `Změnil stav soupisu (${worksheetStatusCs(meta.from)} → ${worksheetStatusCs(meta.to)})${
          meta.comment ? ` – ${meta.comment}` : ''
        }`,
        entity,
        category,
      };

    case 'user:create':
      return { title: 'Vytvořil uživatele', entity, category };
    case 'user:update':
      return { title: 'Upravil uživatele', entity, category };
    case 'user:login':
      return { title: 'Přihlásil se', entity: null, category: 'Ostatní' };
    case 'user:logout':
      return { title: 'Odhlásil se', entity: null, category: 'Ostatní' };
    case 'user:change_pin':
      return { title: 'Změnil PIN', entity: null, category: 'Úpravy' };

    case 'price_list:price_list_publish':
      return {
        title: `Zveřejnil nový ceník${meta.version ? ` (verze ${meta.version})` : ''}`,
        entity,
        category: 'Ceník',
      };

    default:
      return { title: `${log.action} (${log.entityType ?? '—'})`, entity, category };
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

/** Podkategorie pro ChangeLog záznam – podle pole, které se měnilo. */
function categoryForChange(fieldName: string | null): LogCategory {
  if (fieldName === 'status') return 'Stav';
  if (fieldName === 'floorId') return 'Přesuny';
  return 'Úpravy';
}

export function describeChange(
  log: ChangeLike,
): { title: string; entity: EntityRef; category: LogCategory } {
  const field = CHANGE_FIELD_LABELS[log.fieldName ?? ''] ?? log.fieldName ?? 'pole';
  const entity = { type: log.entityType as LogEntityType, id: log.entityId };
  const category = categoryForChange(log.fieldName);

  if (log.entityType === 'worksheet' && log.fieldName === 'status') {
    return {
      title: `Stav soupisu: ${worksheetStatusCs(log.oldValue)} → ${worksheetStatusCs(log.newValue)}`,
      entity,
      category,
    };
  }
  if (log.entityType === 'seal' && log.fieldName === 'status') {
    return {
      title: `Stav ucpávky: ${sealStatusCs(log.oldValue)} → ${sealStatusCs(log.newValue)}`,
      entity,
      category,
    };
  }
  if (log.fieldName === 'entries') {
    return { title: 'Upravil prostupy ucpávky', entity, category };
  }
  return {
    title: `Změna pole „${field}": ${log.oldValue ?? '—'} → ${log.newValue ?? '—'}`,
    entity,
    category,
  };
}


