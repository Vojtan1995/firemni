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
