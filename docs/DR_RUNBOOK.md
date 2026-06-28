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
| 2026-06-28 | Doplněny secrets (`BACKUP_AGE_RECIPIENT` repo secret, `BACKUP_AGE_IDENTITY` v prostředí `dr-restore`) a opraven CI (AWS CLI v2). Spuštěn `backup.yml`, poté `dr-restore-test.yml` naživo (run [28336839090](https://github.com/Vojtan1995/firemni/actions/runs/28336839090)). | **✅ Úspěšný živý restore test.** Dešifrování `.dump.age` i privacy-erasure ledgeru, `pg_restore`, FK integritní kontroly (0 orphan seals/photos), reapply GDPR výmazů — vše proběhlo bez chyby. Obnovená data: 20 uživatelů, 10 zakázek, 325 ucpávek, 94 fotek, 0 reapplikovaných výmazů (produkce zatím žádné GDPR výmazy neprovedla). Cesta od triggeru do dokončení restore kroku ~70 s — výrazně pod RTO 4 h. RPO dán intervalem denní zálohy (≤24 h), poslední záloha před testem proběhla týž den. Mimochodem objeven a opraven edge-case bug: `age -d` u zcela prázdného plaintextu (žádné GDPR výmazy) nevytvoří výstupní soubor i přes exit 0 (lazy file creation) — workflow nyní v tom případě doplní prázdný soubor sám. |
