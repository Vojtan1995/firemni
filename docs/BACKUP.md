# Zálohy a obnova (UNIFAST Ucpávky)

## Produkční DR cesta

Produkční obnova stojí na GitHub Actions a izolovaném Cloudflare R2 backup bucketu. Backend nedrží backup R2 credentials; workflow po doběhu jen reportuje stav do aplikace přes `POST /api/internal/backup-runs` a `BACKUP_REPORT_TOKEN`.

### Databáze

Workflow [`.github/workflows/backup.yml`](../.github/workflows/backup.yml) běží denně v `02:00 UTC` a dělá:

1. `pg_dump -Fc --no-owner --no-acl` do `ucpavky_<timestamp>.dump`.
2. `pg_restore --list` jako lokální kontrolu formátu.
3. Šifrování přes `age` do `ucpavky_<timestamp>.dump.age`.
4. `sha256sum` pro šifrovaný soubor.
5. Manifest `ucpavky_<timestamp>.manifest.json`.
6. Export šifrovaného GDPR privacy-erasure ledgeru.
7. Upload do `s3://$BACKUP_S3_BUCKET/backups/ucpavky_<timestamp>/`.
8. Stažení uploadnutých artefaktů zpět z R2 a ověření checksumu/manifestu.
9. Retence: maže snapshoty starší než 30 dní, ale vždy ponechá minimálně posledních 7 snapshotů.
10. Telegram alert při selhání a best-effort zápis `BackupRun(type=db)`.

### Fotky a výkresy

Workflow [`.github/workflows/object-backup.yml`](../.github/workflows/object-backup.yml) denně kopíruje aplikační R2 bucket do backup bucketu pod `objects/<timestamp>/data/`, vytváří `object-manifest.sha256` a kontroluje:

- DB reference na `seal_photos` a `floor_drawings` nesmí chybět v bucketu.
- V bucketu nesmí být objekty bez DB záznamu.
- Počet objektů nesmí náhle spadnout o více než 20 %.
- Obsah existujících objektových klíčů se nesmí měnit.

Výsledek se zapisuje jako `BackupRun(type=object)`.

### Restore test

Workflow [`.github/workflows/dr-restore-test.yml`](../.github/workflows/dr-restore-test.yml) běží týdně v neděli v `05:00 UTC`:

- stáhne nejnovější `.dump.age`,
- ověří checksum,
- dešifruje pomocí `BACKUP_AGE_IDENTITY`,
- obnoví dump do scratch PostgreSQL,
- ověří klíčové počty a FK integritu,
- reaplikuje privacy-erasure ledger,
- zapíše `BackupRun(type=restore_test)`.

## Secrets

Povinné pro DB/object backup:

| Secret | Popis |
| --- | --- |
| `PROD_DATABASE_URL` | Produkční PostgreSQL connection string |
| `BACKUP_S3_BUCKET` | Izolovaný R2 bucket pro zálohy |
| `BACKUP_S3_ENDPOINT` | R2 S3 endpoint |
| `BACKUP_S3_ACCESS_KEY_ID` | R2 key pro backup bucket |
| `BACKUP_S3_SECRET_ACCESS_KEY` | R2 secret pro backup bucket |
| `BACKUP_AGE_RECIPIENT` | Veřejný age recipient pro šifrování |
| `APP_STORAGE_BUCKET` / `APP_STORAGE_ENDPOINT` | Zdrojový bucket fotek/výkresů |
| `APP_STORAGE_READ_ACCESS_KEY_ID` / `APP_STORAGE_READ_SECRET_ACCESS_KEY` | Read-only přístup ke zdrojovému bucketu |

Povinné pro restore test v prostředí `dr-restore`:

| Secret | Popis |
| --- | --- |
| `BACKUP_AGE_IDENTITY` | Privátní age identity pro dešifrování |

Volitelné, ale doporučené:

| Secret | Popis |
| --- | --- |
| `BACKUP_REPORT_URL` | URL produkčního backendu pro zápis `BackupRun` |
| `BACKUP_REPORT_TOKEN` | Token shodný s backend env `BACKUP_REPORT_TOKEN` |
| `BACKUP_HEALTH_TOKEN` | Token pro externí monitor `GET /api/internal/backup-health` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | Alerty při selhání workflow |

## Admin přehled

- `GET /api/admin/backup-status` vrací poslední DB zálohu, objektovou zálohu a restore test.
- `GET /api/internal/backup-health` s bearer tokenem `BACKUP_HEALTH_TOKEN` vrací `200`, pokud jsou DB/object zálohy mladší než 30 hodin a restore test mladší než 8 dní; jinak vrací `503`.
- `GET /api/logs/backups` vrací admin log sekci “Zálohy”.
- `BackupRun` je produkční zdroj pravdy pro stav off-site záloh.
- `BackupLog` je legacy/ad-hoc evidence lokálních dumpů.

## Lokální backup v aplikaci

`POST /api/admin/backup` a `BACKUP_ENABLED` používají `backend/src/services/backup.service.ts`, který ukládá `.dump` na lokální disk. To není produkční DR cesta. V produkci je lokální backup zakázaný, pokud není explicitně nastaveno `ALLOW_LOCAL_BACKUP_IN_PRODUCTION=true`.

## Ruční obnova DB

```bash
aws s3 cp "s3://$BACKUP_S3_BUCKET/backups/ucpavky_<timestamp>/ucpavky_<timestamp>.dump.age" . \
  --endpoint-url "$BACKUP_S3_ENDPOINT"
aws s3 cp "s3://$BACKUP_S3_BUCKET/backups/ucpavky_<timestamp>/ucpavky_<timestamp>.dump.age.sha256" . \
  --endpoint-url "$BACKUP_S3_ENDPOINT"

sha256sum -c ucpavky_<timestamp>.dump.age.sha256
age -d -i age-key.txt -o ucpavky_<timestamp>.dump ucpavky_<timestamp>.dump.age
pg_restore --clean --if-exists --no-owner --no-acl -d "$TARGET_DATABASE_URL" ucpavky_<timestamp>.dump
```

Před obnovou produkce vždy zastavit zápisy/backend, pořídit snapshot aktuálního stavu a nejdřív obnovu ověřit ve scratch databázi.
