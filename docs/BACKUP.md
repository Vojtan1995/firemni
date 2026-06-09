# Zálohy databáze (UNIFAST Ucpávky)

## Konfigurace (env)

| Proměnná | Výchozí | Popis |
|----------|---------|--------|
| `BACKUP_ENABLED` | `false` | Zapne periodický scheduler v `index.ts` |
| `BACKUP_DIR` | `./backups` | Adresář pro `.dump` soubory |
| `BACKUP_RETENTION_COUNT` | `7` | Počet úspěšných záloh k uchování |
| `BACKUP_INTERVAL_HOURS` | `24` | Interval automatické zálohy |

Vyžaduje `pg_dump` v PATH a platnou `DATABASE_URL`.

## API (admin)

- `GET /api/admin/backups` — seznam logů záloh
- `POST /api/admin/backup` — ruční spuštění zálohy

Oprávnění: role `admin` (`admin.backup`).

## Railway / cron

Pro produkci bez běžícího scheduleru lze volat:

```bash
curl -X POST https://<host>/api/admin/backup \
  -H "Authorization: Bearer <admin-token>"
```

Nebo nastavit Railway Cron Job se stejným příkazem 1× denně.

## Obnova

```bash
pg_restore -d "$DATABASE_URL" --clean --if-exists ./backups/ucpavky_YYYYMMDD_HHMMSS.dump
```

Před obnovou vždy ověřte cílovou databázi a zálohujte aktuální stav.
