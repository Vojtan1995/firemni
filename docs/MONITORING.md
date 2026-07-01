# Monitoring & alerting (UNIFAST Ucpávky)

Tři vrstvy: **chyby v kódu** (Sentry), **dostupnost** (UptimeRobot na `/ready`)
a **zálohy** (GitHub Actions, viz [BACKUP.md](BACKUP.md)). Všechny alerty tečou do
jednoho **Telegram** chatu.

## Health endpointy

| Endpoint | Co kontroluje | Použití |
|----------|---------------|---------|
| `GET /health` | jen že proces žije | liveness |
| `GET /ready` | DB + storage (R2) | readiness, externí uptime monitor, Railway healthcheck |
| `GET /api/internal/backup-health` | čerstvost DB/object záloh a restore testu | externí monitor záloh; vyžaduje `BACKUP_HEALTH_TOKEN` |

Implementace v [`backend/src/app.ts`](../backend/src/app.ts). `/ready` vrací non-200,
když je nedostupná DB nebo R2 — proto je vhodný cíl monitoringu (pokryje i výpadek
Postgresu/storage, ne jen pád procesu).

## 1. Sentry (chyby v kódu)

Inicializace je hotová v [`backend/src/index.ts`](../backend/src/index.ts) a aktivuje
se automaticky, když je nastavená env proměnná. **Žádná změna kódu není potřeba.**

Nastavení:
1. Založit projekt v Sentry (platforma **Node.js**), zkopírovat DSN.
2. V Railway přidat env proměnnou `SENTRY_DSN=<dsn>` a redeploy.
3. (Volitelně) v Sentry → Alerts nastavit notifikaci na nové issue do Telegramu/e-mailu.

Ověření: vyvolat testovací chybu a zkontrolovat, že event dorazil do dashboardu.

## 2. UptimeRobot (dostupnost)

1. Nový monitor typu **HTTP(s)**, URL = `https://<railway-host>/ready`, interval **5 min**.
2. Alert contact = **Telegram** (UptimeRobot má nativní integraci — použij stejný bot/chat
   jako u záloh).
3. Volitelně zapnout i monitor na frontend/APK URL, pokud je veřejná.

UptimeRobot pošle „Down" při výpadku a „Up" po obnově.

## 3. Telegram alert hub

Jeden bot obsluhuje zálohy i uptime.

Vytvoření:
1. V Telegramu napsat **@BotFather** → `/newbot` → získat **bot token**.
2. Botovi poslat libovolnou zprávu, pak otevřít
   `https://api.telegram.org/bot<TOKEN>/getUpdates` a z odpovědi vyčíst
   `result[].message.chat.id` → to je **chat ID**.
3. Token + chat ID uložit:
   - jako GitHub secrets `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` (pro backup.yml),
   - jako alert contact v UptimeRobot.

## Runbook — co dělat při alertu

| Alert | Kde hledat | Akce |
|-------|-----------|------|
| 🔴 DB záloha selhala | GitHub → Actions → Encrypted DB Backup → log runu; aplikace → Logy → Zálohy | Zkontrolovat `pg_dump`/šifrování/upload/verify krok; ověřit `PROD_DATABASE_URL`, `BACKUP_AGE_RECIPIENT` a `BACKUP_S3_*`; spustit ručně přes *Run workflow* |
| 🔴 Objektová záloha selhala | GitHub → Actions → R2 Object Backup; aplikace → Logy → Zálohy | Zkontrolovat DB reference proti R2 objektům, mass-deletion guard a credentials zdrojového/backup bucketu |
| 🔴 Restore test selhal | GitHub → Actions → Weekly DR Restore Test; aplikace → Logy → Zálohy | Prověřit poslední `.dump.age`, `BACKUP_AGE_IDENTITY`, `pg_restore` a privacy ledger |
| Uptime „Down" | Railway → Deployments / Logs, případně `/ready` v prohlížeči | Zjistit, zda je dole DB nebo R2; restart služby; eskalovat |
| Sentry nové issue | Sentry dashboard (stack trace, request, user) | Triáž závažnosti; opravit / vytvořit issue |

### Disaster recovery (rychlá reference)

Obnova z poslední zálohy v R2 je popsaná v [BACKUP.md](BACKUP.md). Týdenní restore test běží automaticky přes `dr-restore-test.yml` a zapisuje výsledek do `BackupRun`.

- Poslední doložený živý restore test: 2026-06-28, přibližně 70 s do dokončení restore kroku.
