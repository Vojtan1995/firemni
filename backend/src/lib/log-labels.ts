/**
 * PĹ™eklad syrovĂ˝ch audit zĂˇznamĹŻ (ActivityLog / ChangeLog) na lidsky ÄŤitelnĂ© ÄŤeskĂ© vÄ›ty,
 * podkategorii pro skupinovĂ© zobrazenĂ­ v UI a odkaz na entitu, na kterou se dĂˇ v UI
 * prokliknout. SdĂ­leno endpointy v logs.routes.ts.
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

/** Podkategorie pro skupinovĂ© zobrazenĂ­ logĹŻ v UI (ÄŤesky, bez syrovĂ˝ch nĂˇzvĹŻ akcĂ­). */
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

/** Akce, kterĂ© mÄ›nĂ­ data (patĹ™Ă­ do â€žHistorie zmÄ›n"), nikoliv jen pĹ™ihlĂˇĹˇenĂ­/odhlĂˇĹˇenĂ­. */
const NON_MUTATION_ACTIONS = new Set(['login', 'logout', 'change_pin']);

export function isDataMutation(action: string): boolean {
  return !NON_MUTATION_ACTIONS.has(action);
}

/**
 * Pole ChangeLogu, kterĂˇ jsou jen internĂ­ technickĂ© ĂşÄŤetnictvĂ­ (odvozenĂ©
 * pĹ™Ă­znaky), ne skuteÄŤnĂˇ Ăşprava, kterou udÄ›lal ÄŤlovÄ›k â€” v â€žHistorii zmÄ›n" je
 * potlaÄŤĂ­me, aby tam nebyl Ĺˇum vedle smysluplnĂ˝ch akcĂ­ (vytvoĹ™enĂ­, Ăşprava,
 * stav, foto, vĂ˝kresâ€¦). `markerPlacementPending` se pĹ™epoÄŤĂ­tĂˇ automaticky pĹ™i
 * kaĹľdĂ©m umĂ­stÄ›nĂ­ znaÄŤky / nahrĂˇnĂ­ vĂ˝kresu, takĹľe by zaplevelovalo log
 * duplicitnĂ­m zĂˇznamem ke kaĹľdĂ© takovĂ© akci, kterĂˇ uĹľ mĂˇ svĹŻj vlastnĂ­
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

/** ÄŚeskĂ© hodnoty stavu ucpĂˇvky â€“ pro zobrazenĂ­ v titulcĂ­ch logĹŻ (ĹľĂˇdnĂ© syrovĂ© enum hodnoty). */
const SEAL_STATUS_LABELS: Record<string, string> = {
  draft: 'RozpracovanĂˇ',
  checked: 'ZkontrolovanĂˇ',
  invoiced: 'VyfakturovanĂˇ',
};

/** ÄŚeskĂ© hodnoty stavu soupisu â€“ pro zobrazenĂ­ v titulcĂ­ch logĹŻ. */
const WORKSHEET_STATUS_LABELS: Record<string, string> = {
  draft: 'RozpracovanĂ˝',
  submitted: 'OdevzdanĂ˝',
  reviewed: 'SchvĂˇlenĂ˝',
  ready_for_invoice: 'PĹ™ipravenĂ˝ k fakturaci',
  invoiced: 'VyfakturovanĂ˝',
  archived: 'ArchivovanĂ˝',
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
  return label ? ` ve stavbÄ› ${label}` : '';
}

function worksheetAudienceCs(value: unknown) {
  return value === 'customer' ? 'pro zĂˇkaznĂ­ka' : 'pro pracovnĂ­ky';
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
  return ` za obdobĂ­ ${from || 'â€”'} aĹľ ${to || 'â€”'}`;
}

/** Podkategorie pro ActivityLog akci â€“ podle entityType:action. */
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
      return { title: `VytvoĹ™il stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category };
    case 'job:update':
      return { title: `Upravil stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category };
    case 'job:archive':
      return { title: `Archivoval stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category: 'Smazání a obnova' };
    case 'job:unarchive':
      return { title: `Obnovil stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''} z archivu`, entity, category: 'Smazání a obnova' };
    case 'job:complete':
      return { title: `OznaÄŤil stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''} jako dokonÄŤenou`, entity, category: 'Stav' };
    case 'job:activate':
      return { title: `Aktivoval stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category: 'Stav' };
    case 'job:soft_delete':
      return { title: `Smazal stavbu${jobLabel(meta) ? ` ${jobLabel(meta)}` : ''}`, entity, category: 'Smazání a obnova' };

    case 'job_floor:create':
      return { title: `VytvoĹ™il patro ${floorLabel(meta)}${inJob(meta)}`, entity, category };
    case 'job_floor:update':
      return { title: `Upravil patro ${floorLabel(meta)}${inJob(meta)}`, entity, category };
    case 'job_floor:soft_delete':
      return { title: `Smazal patro ${floorLabel(meta)}${inJob(meta)}`, entity, category };
    case 'job_floor:floor_drawing_upload':
      return {
        title: `${meta.replaced ? 'Nahradil' : 'NahrĂˇl'} vĂ˝kres patra ${floorLabel(meta)}${inJob(meta)}${
          meta.fileName ? ` (${meta.fileName})` : ''
        }`,
        entity,
        category,
      };
    case 'job_floor:floor_drawing_delete':
      return { title: `Smazal vĂ˝kres patra ${floorLabel(meta)}${inJob(meta)}`, entity, category };

    case 'worksheet:worksheet_create':
      return {
        title: `VytvoĹ™il soupis ${worksheetAudienceCs(meta.audience)}${inJob(meta)}${workersLabel(meta)}${periodLabel(meta)}`,
        entity,
        category,
      };
    case 'worksheet:worksheet_add_items':
      return {
        title: `PĹ™idal poloĹľky do soupisu${inJob(meta)} (${meta.count ?? '?'})`,
        entity,
        category,
      };
    case 'worksheet:worksheet_status':
      return {
        title: `ZmÄ›nil stav soupisu ${worksheetAudienceCs(meta.audience)}${inJob(meta)}${workersLabel(meta)}: ${worksheetStatusCs(meta.from)} â†’ ${worksheetStatusCs(meta.to)}${
          meta.comment ? ` â€“ ${meta.comment}` : ''
        }`,
        entity,
        category,
      };
    case 'worksheet:worksheet_delete':
      return {
        title: `Smazal rozpracovanĂ˝ soupis ${worksheetAudienceCs(meta.audience)}${inJob(meta)}${workersLabel(meta)}${periodLabel(meta)}`,
        entity,
        category,
      };
    case 'seal:create':
      return { title: 'VytvoĹ™il novou ucpĂˇvku', entity, category };
    case 'seal:update':
      return { title: 'Upravil ucpĂˇvku', entity, category };
    case 'seal:status_change':
      return {
        title: `ZmÄ›nil stav ucpĂˇvky (${sealStatusCs(meta.from)} â†’ ${sealStatusCs(meta.to)})`,
        entity,
        category,
      };
    case 'seal:override_locked_edit':
      return { title: `Upravil zamÄŤenou ucpĂˇvku (dĹŻvod: ${meta.reason ?? 'â€”'})`, entity, category };
    case 'seal:bulk_move':
      return { title: 'PĹ™esunul ucpĂˇvku na jinĂ© patro', entity, category };
    case 'seal:soft_delete':
      return { title: 'Smazal ucpĂˇvku', entity, category };
    case 'seal:restore':
      return { title: 'Obnovil ucpĂˇvku z koĹˇe', entity, category };
    case 'seal:photo_upload':
      return { title: 'PĹ™idal fotku k ucpĂˇvce', entity, category };
    case 'seal:seal_marker_upsert':
      return { title: 'UmĂ­stil/pĹ™esunul znaÄŤku na vĂ˝kresu', entity, category };
    case 'seal:seal_marker_delete':
      return { title: 'Odstranil znaÄŤku z vĂ˝kresu', entity, category };

    case 'seal_repair:create':
      return { title: 'VytvoĹ™il opravu ucpĂˇvky', entity, category };

    case 'seal_photo:photo_delete':
      return {
        title: 'Smazal fotku ucpĂˇvky',
        entity: meta.sealId ? { type: 'seal', id: String(meta.sealId) } : null,
        category,
      };

    case 'job:create':
      return { title: 'VytvoĹ™il zakĂˇzku', entity, category };
    case 'job:update':
      return { title: 'Upravil zakĂˇzku', entity, category };
    case 'job:archive':
      return { title: 'Archivoval zakĂˇzku', entity, category: 'Smazání a obnova' };
    case 'job:unarchive':
      return { title: 'Obnovil zakĂˇzku z archivu', entity, category: 'Smazání a obnova' };
    case 'job:complete':
      return { title: 'OznaÄŤil zakĂˇzku jako dokonÄŤenou', entity, category: 'Stav' };
    case 'job:activate':
      return { title: 'Aktivoval zakĂˇzku', entity, category: 'Stav' };
    case 'job:soft_delete':
      return { title: 'Smazal zakĂˇzku', entity, category: 'Smazání a obnova' };

    case 'job_floor:create':
      return { title: 'VytvoĹ™il patro', entity, category };
    case 'job_floor:update':
      return { title: 'Upravil patro', entity, category };
    case 'job_floor:soft_delete':
      return { title: 'Smazal patro', entity, category };
    case 'job_floor:floor_drawing_upload':
      return { title: 'NahrĂˇl vĂ˝kres patra', entity, category };
    case 'job_floor:floor_drawing_delete':
      return { title: 'Smazal vĂ˝kres patra', entity, category };

    case 'worksheet:worksheet_create':
      return { title: 'VytvoĹ™il soupis prĂˇce', entity, category };
    case 'worksheet:worksheet_add_items':
      return { title: `PĹ™idal poloĹľky do soupisu (${meta.count ?? '?'})`, entity, category };
    case 'worksheet:worksheet_status':
      return {
        title: `ZmÄ›nil stav soupisu (${worksheetStatusCs(meta.from)} â†’ ${worksheetStatusCs(meta.to)})${
          meta.comment ? ` â€“ ${meta.comment}` : ''
        }`,
        entity,
        category,
      };

    case 'user:create':
      return { title: 'VytvoĹ™il uĹľivatele', entity, category };
    case 'user:update':
      return { title: 'Upravil uĹľivatele', entity, category };
    case 'user:login':
      return { title: 'PĹ™ihlĂˇsil se', entity: null, category: 'Ostatní' };
    case 'user:logout':
      return { title: 'OdhlĂˇsil se', entity: null, category: 'Ostatní' };
    case 'user:change_pin':
      return { title: 'ZmÄ›nil PIN', entity: null, category: 'Úpravy' };

    case 'price_list:price_list_publish':
      return {
        title: `ZveĹ™ejnil novĂ˝ cenĂ­k${meta.version ? ` (verze ${meta.version})` : ''}`,
        entity,
        category: 'Ceník',
      };

    default:
      return { title: `${log.action} (${log.entityType ?? 'â€”'})`, entity, category };
  }
}

const CHANGE_FIELD_LABELS: Record<string, string> = {
  status: 'stav',
  floorId: 'patro',
  reviewStatus: 'stav revize',
  note: 'poznĂˇmka',
  internalNote: 'internĂ­ poznĂˇmka',
  sealNumber: 'ÄŤĂ­slo ucpĂˇvky',
  system: 'systĂ©m',
  construction: 'konstrukce',
  location: 'umĂ­stÄ›nĂ­',
  fireRating: 'poĹľĂˇrnĂ­ odolnost',
  openingLengthMm: 'dĂ©lka otvoru',
  openingWidthMm: 'ĹˇĂ­Ĺ™ka otvoru',
  markerPlacementPending: 'ÄŤekĂˇ na zakreslenĂ­',
  entries: 'prostupy',
};

/** Podkategorie pro ChangeLog zĂˇznam â€“ podle pole, kterĂ© se mÄ›nilo. */
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
      title: `Stav soupisu: ${worksheetStatusCs(log.oldValue)} â†’ ${worksheetStatusCs(log.newValue)}`,
      entity,
      category,
    };
  }
  if (log.entityType === 'seal' && log.fieldName === 'status') {
    return {
      title: `Stav ucpĂˇvky: ${sealStatusCs(log.oldValue)} â†’ ${sealStatusCs(log.newValue)}`,
      entity,
      category,
    };
  }
  if (log.fieldName === 'entries') {
    return { title: 'Upravil prostupy ucpĂˇvky', entity, category };
  }
  return {
    title: `ZmÄ›na pole â€ž${field}": ${log.oldValue ?? 'â€”'} â†’ ${log.newValue ?? 'â€”'}`,
    entity,
    category,
  };
}


