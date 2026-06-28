# Disaster recovery runbook

## Cíle

- RPO: nejvýše 24 hodin.
- RTO: nejvýše 4 hodiny.
- Produkce se neotevře před DB, R2 a privacy kontrolou.

## Vyhlášení

Incident commander: DOPLNIT.  
Technický vykonavatel: DOPLNIT.  
Schvalovatel návratu: DOPLNIT.  
Komunikační kanál: DOPLNIT.

## Obnova

1. Zastavit zápisy nebo backend.
2. Pořídit forenzní snapshot současného stavu, pokud je dostupný.
3. Vybrat nejnovější backup s platným manifestem a checksumem.
4. Ověřit dostupnost `age` identity z firemního trezoru.
5. Dešifrovat `.dump.age`; privátní klíč nikdy nelogovat.
6. Obnovit přes `pg_restore --clean --if-exists --no-owner --no-acl`.
7. Spustit FK kontrolu a počty kritických tabulek.
8. Obnovit/ověřit R2 objekty podle manifestu.
9. Načíst nejnovější privacy erasure ledger a znovu aplikovat výmazy.
10. Spustit `/ready`, backend smoke a klientský login/sync/photo/export smoke.
11. Schvalovatel povolí návrat uživatelů.
12. Zapsat dosažené RPO/RTO a odchylky.

## Selhání

- Neplatný poslední backup: použít předchozí platný a zapsat skutečné RPO.
- Chybějící age klíč: eskalovat na druhý trezor; nezkoušet obcházet šifrování.
- Jiná PG verze: obnovovat klientem/serverem stejné nebo novější major verze.
- Chybějící R2 objekt: obnovit ze snapshot prefixu; DB řádek nemažte bez schválení.
- Nepovedený restore: zničit cílovou scratch DB a opakovat; nepřepisovat zdroj.

## Čtvrtletní cvičení

Zaznamenat datum, účastníky, backup timestamp, začátek, konec, RPO, RTO, počty
tabulek, vzorek objektů, nalezené problémy a jejich vlastníky.

## Záznam o ověření obnovy

| Datum | Co se dělo | Výsledek |
|---|---|---|
| 2026-06-28 | Kontrola běhů `dr-restore-test.yml` a `backup.yml` na GitHub Actions. | **Nalezena CI závada:** krok instalace selhával na `apt-get install awscli` — balík `awscli` už není v repozitáři Ubuntu 24.04. Postihovalo `backup.yml`, `dr-restore-test.yml` i `object-backup.yml`. **Opraveno:** instalace přes oficiální AWS CLI v2 (zip z `awscli.amazonaws.com`). |
| 2026-06-28 | Kontrola záloh. | `backup.yml` navíc selhával na `Missing AGE_RECIPIENT` — chybí/odstraněn repo secret `BACKUP_AGE_RECIPIENT` (veřejný `age` klíč). Poslední úspěšná záloha: 2026-06-27. **Akce vlastníka:** doplnit secret. |

### Co zbývá k „zelenému" živému testu obnovy

1. Sloučit opravu workflow (AWS CLI v2) do `main` — bez ní se `dr-restore-test` ani `backup` nedostanou za instalační krok.
2. Doplnit chybějící secrets:
   - `backup.yml`: `BACKUP_AGE_RECIPIENT` (+ `PROD_DATABASE_URL`, `BACKUP_S3_*`).
   - prostředí `dr-restore`: `AGE_IDENTITY` (privátní klíč), `BACKUP_S3_*`, `TARGET_DATABASE_URL`.
3. Spustit ručně: `gh workflow run dr-restore-test.yml` (potřebuje existující šifrovanou zálohu v R2 — tj. nejdřív zelený `backup.yml`).
4. Po zeleném běhu sem zapsat dosažené RPO/RTO a počty tabulek a teprve pak v `AUDIT_REPORT_NASAZENI.md` přepnout bod „test obnovy" na ☑.
