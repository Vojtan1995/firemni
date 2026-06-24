# Zálohy databáze (UNIFAST Ucpávky)

## Primární cesta: GitHub Actions → R2 (off-site)

Denní automatická záloha běží **mimo aplikaci** přes GitHub Actions
([`.github/workflows/backup.yml`](../.github/workflows/backup.yml)) a ukládá
komprimovaný dump na Cloudflare R2. Je nezávislá na běhu Railway služby — proto je
to hlavní disaster-recovery cesta.

Co workflow dělá:
1. `pg_dump "$PROD_DATABASE_URL" | gzip` → `ucpavky_<timestamp>.sql.gz`
2. `gunzip -t` ověří integritu gzipu (poškozený dump = červené workflow)
3. upload na `s3://<bucket>/backups/` (R2, S3-kompatibilní)
4. promazání záloh starších než 30 dní
5. při jakémkoli selhání → **Telegram alert** (viz [MONITORING.md](MONITORING.md))

Plán: `cron: '0 2 * * *'` (2:00 UTC = 4:00 Prague letní čas). Lze i ručně přes
*Actions → DB Backup → Run workflow* (`workflow_dispatch`).

### Potřebné GitHub secrets

Settings → Secrets and variables → Actions:

| Secret | Popis |
|--------|-------|
| `PROD_DATABASE_URL` | Connection string produkční DB (z Railway) |
| `BACKUP_S3_BUCKET` | Název R2 bucketu pro zálohy (**samostatný**, ne foto-bucket) |
| `BACKUP_S3_ENDPOINT` | `https://<account-id>.r2.cloudflarestorage.com` |
| `BACKUP_S3_ACCESS_KEY_ID` | R2 S3 API key ID (read/write na bucket) |
| `BACKUP_S3_SECRET_ACCESS_KEY` | R2 S3 API secret |
| `TELEGRAM_BOT_TOKEN` | Bot token pro alert při selhání (volitelné) |
| `TELEGRAM_CHAT_ID` | Cílový chat pro alert (volitelné) |

> Pokud některý z `PROD_DATABASE_URL` / `BACKUP_S3_*` chybí, workflow **schválně
> spadne** (`::error::`), ať není tichá zelená iluze běžících záloh.

Doporučeno: na R2 bucketu nastavit **lifecycle rule** na auto-mazání objektů
> 35 dní jako pojistku k prune kroku.

## Obnova z R2 (disaster recovery)

```bash
# 1) stáhnout poslední dump
aws s3 cp "s3://$BACKUP_S3_BUCKET/backups/ucpavky_<timestamp>.sql.gz" . \
  --endpoint-url "$BACKUP_S3_ENDPOINT"

# 2) ověřit integritu a rozbalit
gunzip -t ucpavky_<timestamp>.sql.gz
gunzip ucpavky_<timestamp>.sql.gz

# 3) naimportovat (plain SQL dump → psql)
psql "$TARGET_DATABASE_URL" < ucpavky_<timestamp>.sql
```

Před obnovou do produkce vždy nejdřív zálohuj aktuální stav a otestuj obnovu do
scratch databáze (počty řádků v klíčových tabulkách).

## Doplňková cesta: in-process scheduler (NE pro DR)

`backend/src/services/backup.service.ts` umí `pg_dump -Fc` přímo z běžící appky,
ale ukládá na **lokální/ephemeral disk** (na Railway se ztratí při redeployi).
Slouží jen pro lokální/ad-hoc zálohy a evidenci v `BackupLog` — **ne** jako
off-site DR. Pro produkci spoléhej na GitHub Actions výše.

Konfigurace (env):

| Proměnná | Výchozí | Popis |
|----------|---------|--------|
| `BACKUP_ENABLED` | `false` | Zapne periodický scheduler v `index.ts` |
| `BACKUP_DIR` | `./backups` | Adresář pro `.dump` soubory |
| `BACKUP_RETENTION_COUNT` | `7` | Počet úspěšných záloh k uchování |
| `BACKUP_INTERVAL_HOURS` | `24` | Interval automatické zálohy |

API (admin, oprávnění `admin.backup`):
- `GET /api/admin/backups` — seznam logů záloh
- `POST /api/admin/backup` — ruční spuštění zálohy

Obnova `.dump` (custom formát):
```bash
pg_restore -d "$DATABASE_URL" --clean --if-exists ./backups/ucpavky_YYYYMMDD_HHMMSS.dump
```
