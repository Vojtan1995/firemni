# P0 implementation register — etapa 1

Datum zahájení: 2026-06-27  
Rozsah: governance, DR, MFA, GDPR, load test, security test a rollout.  
Odloženo: šifrování lokálních dat a evidence ETA/DoP/CE.

## Vlastníci

Před produkční aktivací musí vedení doplnit jména. Zástupce nesmí být totožný s
hlavním vlastníkem.

| Oblast | Hlavní vlastník | Zástupce | Schvalovatel |
|---|---|---|---|
| Aplikace | DOPLNIT | DOPLNIT | DOPLNIT |
| Infrastruktura | DOPLNIT | DOPLNIT | DOPLNIT |
| Zálohy a DR | DOPLNIT | DOPLNIT | DOPLNIT |
| Bezpečnost | DOPLNIT | DOPLNIT | DOPLNIT |
| Osobní údaje | DOPLNIT | DOPLNIT | DOPLNIT |
| Produkční incidenty | DOPLNIT | DOPLNIT | DOPLNIT |

## Kontrolní registr

`done` znamená implementováno a automaticky ověřeno. `external` znamená, že
repozitář obsahuje připravený proces, ale výsledek vyžaduje externí službu nebo
schválení člověkem.

| ID | Riziko | Řešení/důkaz | Stav | Residual risk | Další kontrola |
|---|---|---|---|---|---|
| GOV-01 | Nejasná odpovědnost | Tabulka vlastníků výše | external | Jména nejsou doplněna | před stagingem |
| GOV-02 | Formální uzavírání bez důkazu | Tento registr + release gate | done | Manuální kontrola důkazů | každý release |
| GOV-03 | Testování nad produkcí | `STAGING_RUNBOOK.md` | external | Cloud zdroje je nutné založit | před load/pentest |
| GOV-04 | Neřízený release | `P0_ROLLOUT_RUNBOOK.md` | done | Schválení je lidský krok | každý release |
| DR-01 | Neznámý RPO/RTO | RPO 24 h, RTO 4 h | done | Nutné potvrdit cvičením | čtvrtletně |
| DR-02 | Neověřitelný/čitelný dump | custom dump, age, checksum, manifest | done | Klíče musí být v trezorech | týdně |
| DR-03 | R2 není zálohované | `object-backup.yml` | external | Nutné nastavit buckets/secrets | denně |
| DR-04 | Záloha bez restore testu | `dr-restore-test.yml` | external | GitHub environment musí mít identity | týdně |
| DR-05 | Neznámý reálný RTO | `DR_RUNBOOK.md` | external | Vyžaduje čtvrtletní cvičení | čtvrtletně |
| MFA-01..08 | Slabý admin login | TOTP, recovery, step-up, testy | done | TOTP není phishing-resistant | každý release |
| GDPR-01 | Neúplná ROPA | `GDPR_GOVERNANCE.md` | external | Právní tituly musí schválit správce | ročně |
| GDPR-02 | Nejasná retence | konfigurovatelná retence + politika | external | Business lhůty musí být schváleny | ročně |
| GDPR-03 | Neprověření dodavatelé | registr zpracovatelů | external | DPA/regiony nejsou potvrzeny | ročně |
| GDPR-04..08 | Práva, logy, výmaz | API, notice gate, redakce, ledger | done | Externí ledger vzniká až po backup jobu | každý release |
| LOAD-01..06 | Neznámá kapacita | `load/k6` | external | K6 musí proběhnout na stagingu | před rolloutem |
| PEN-01..03 | Neřízené security testy | threat model + CI gate | done | Automatika nenahrazuje pentest | každý release |
| PEN-04..06 | Nezávislý pentest | scope a SLA | external | Nutný externí tester a retest | před rolloutem |
| REL-01..05 | Rizikový rollout | rollout runbook | external | 72h monitoring a schválení | při rollout |

## Odložené P0

| Riziko | Dočasné opatření | Zakázané tvrzení |
|---|---|---|
| Lokální SQLite, fotky a plány nejsou aplikačně šifrované | OS app sandbox, secure storage tokenu, řízená zařízení, okamžitá deaktivace ztraceného účtu | „Data na zařízení jsou aplikačně šifrovaná“ |
| Chybí ETA/DoP/CE a kvalifikace | Technická data, fotografie, audit a ruční firemní evidence | „Aplikace prokazuje úplnou shodu výrobku/montáže“ |

Celé původní P0 nesmí být označeno za uzavřené, dokud tyto dva body zůstávají.

## Lokální implementační důkazy — 2026-06-27

- Backend: `npm test` — 51 sad, 331 testů, vše prošlo.
- Frontend bez síťové runtime sady: `flutter test` — 176 testů, vše prošlo.
- Flutter analyzer: žádná chyba ani warning; 18 stávajících lint informací.
- Prisma: všech 32 migrací úspěšně aplikováno na novou prázdnou DB; stejný gate je v CI.
- MFA testy: enrollment, expirace challenge, replay TOTP, recovery, step-up a export/výmaz.
- Startup gate: odmítne povinné MFA bez dvou plně připravených adminů.
- Redakční testy: tokeny, hesla/PIN, MFA/recovery údaje, Sentry body a identita.

Tyto důkazy neplní externí gate označené `external`: zejména skutečný restore v
cloudu, RPO/RTO cvičení, právní/DPO schválení, load run, externí pentest/retest,
doplnění vlastníků a produkční 72hodinové sledování.
