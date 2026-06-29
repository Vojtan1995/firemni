
# Kompletní projektová dokumentace - aplikace pro evidenci požárních ucpávek

> **Poslední aktualizace:** 2026-06-29 – aktuální role `worker`/`vedeni`/`admin`, admin MFA, Android release hardening a per-user lokální fotky.

## 1. Shrnutí projektu
Cílem je vytvořit interní firemní aplikaci pro evidenci požárních ucpávek a prostupů. Aplikace bude používaná přibližně 15 pracovníky v terénu a 4 lidmi z vedení nebo účetního oddělení. Má běžet primárně na Androidu a Windows.

Nejdůležitější požadavek není počet funkcí, ale rychlé zadávání v terénu. Současný problém je pomalá aplikace, mnoho kroků, posouvání mezi stránkami a ruční vypisování. Nová aplikace musí používat rychlé tlačítkové volby, minimum textového zadávání a spolehlivý offline režim.

## 2. Hlavní principy
- Data se nikdy nesmí ztratit.
- Všechno se nejdříve ukládá lokálně a teprve potom synchronizuje.
- Worker může editovat pouze rozpracované ucpávky.
- Vedení kontroluje data, fotky a statusy včetně fakturačního workflow.
- Admin je nouzový superuživatel.
- Žádné tvrdé mazání dat v první verzi.
- Všechny důležité akce se logují.
- Cursor nesmí dostat pokyn typu "udělej celou aplikaci najednou".

## 3. Role
Implementované role v systému (`UserRole`):

| Role | Kód | Popis | Hlavní práva |
|---|---|---|---|
| Pracovník | `worker` | Pracovník v terénu | ucpávky (vlastní), fotky, sync, vlastní soupisy, export vlastních dat |
| Vedení | `vedeni` | Stavby, kontrola, management | CRUD stavby/patra, kontrola statusů ucpávek i soupisů, export, správa uživatelů (kromě admin) |
| Admin | `admin` | Nouzový superuživatel | vše + koš/obnova, plná správa uživatelů včetně admin účtů |

Poznámka: role `ucetni` byla odstraněna; její fakturační oprávnění převzala role `vedeni`.

Testovací účty (seed): `worker1`, `worker2`, `vedeni`, `admin`. Běžné role používají PIN; admin po zapnutí produkčního MFA používá silné heslo a TOTP.

## 4. Workflow workerů
1. Přihlášení jménem a PINem.
2. Automatická synchronizace po přihlášení.
3. Hlavní menu: Stavba, Synchronizace, Profil, Nápověda.
4. Zadání 8místného čísla stavby.
5. Výběr patra vytvořeného vedením.
6. Seznam ucpávek na patře - primárně pouze čísla s malými barevnými indikátory.
7. Přidání nové ucpávky nebo otevření existující.
8. Vyplnění formuláře.
9. Vyfocení nebo nahrání fotky.
10. Lokální uložení.
11. Automatická nebo ruční synchronizace.

## 5. Stavby a patra
Stavba má unikátní 8místné číslo. Toto číslo pracovníkům sděluje vedení. Worker stavbu nezakládá. Pokud číslo stavby neexistuje, aplikace zobrazí chybu.

Patra zakládá pouze vedení nebo admin, aby v datech nevznikal nepořádek. Worker si patro pouze vybírá.

Pole stavby:
- 8místné číslo stavby
- název
- adresa nebo poznámka
- seznam pater
- aktivní / archivovaná

## 6. Seznam ucpávek
Na patře má být seznam čísel ucpávek. Kvůli rychlosti nemá být seznam zahlcen detaily. Doporučení je přidat malé barevné indikátory:

| Indikátor | Význam |
|---|---|
| žlutá | Rozpracováno |
| zelená | Zkontrolováno |
| modrá | Fakturováno |
| červená / varování | Konflikt nebo sync problém |

## 7. Formulář ucpávky
Jedna ucpávka má jedno číslo, jeden systém, společnou konstrukci, umístění, požární odolnost a společné fotky. Uvnitř může mít více prostupů.

Hlavní data ucpávky:
- číslo ucpávky, formát jen číslo
- systém
- konstrukce: Beton/Cihla nebo SDK/PUR
- umístění: Stěna, Strop, Podlaha, Šachta
- požární odolnost: 60 min, 90 min, 120 min
- poznámka
- fotky

Prostup:
- typ prostupu: EL.V., PVC, VZT, PROSTUP, OCEL
- rozměr: předvolby + vlastní textové pole
- počet kusů: celé číslo
- izolace: žádná, hořlavá, nehořlavá
- materiály: více materiálů

## 8. UX formuláře
Nepoužívat klasické dropdowny jako hlavní ovládání. Lepší jsou chipy nebo tlačítka přímo na obrazovce.

Příklad systému:
- Intuseal
- Hilti
- Fischer
- Protecta
- Dunamenti

Po výběru systému se zobrazí materiály daného systému. Každá věc, která se vybírá, má mít 4 až 5 nejpoužívanějších hodnot a možnost vlastní hodnoty.

Po uložení se nemá automaticky otevírat další ucpávka. Lepší je zobrazit potvrzení s volbou Přidat další nebo Zpět na seznam.

## 9. Fotky
Fotky jsou kritické, protože vedení kontroluje každou ucpávku a fotky slouží i jako důkaz pro zákazníka.

Pravidla:
- minimálně jedna hlavní fotka
- možnost více fotek
- fotky patří k celé ucpávce, ne k jednotlivým prostupům
- worker nemůže již nahrané fotky mazat ani měnit
- worker může kdykoliv přidat další fotku k rozpracované ucpávce
- ukládat metadata: kdo a kdy fotku přidal
- fotky zobrazovat až v detailu ucpávky

Doporučení:
- komprimovat fotky na rozumnou velikost
- zachovat kvalitu pro kontrolu
- podporovat JPG, JPEG, PNG, WEBP a podle možností HEIC
- na serveru ukládat sjednoceně jako JPG nebo WEBP
- do databáze neukládat binární data ani base64, pouze metadata a cestu

## 10. Statusy
### 10.1 Ucpávky (prostupy)
Finální statusový tok:
Rozpracováno (`draft`) → Zkontrolováno (`checked`) → Fakturováno (`invoiced`)

Pravidla:
- Worker po uložení vytváří rozpracovanou ucpávku.
- Ucpávka je hotová až po kontrole vedením.
- Vedení může nechat ucpávku rozpracovanou, pokud je potřeba něco dořešit.
- Vedení může zkontrolovanou ucpávku vrátit zpět do rozpracováno.
- Worker nedostává žádné notifikace ani diskuzní vlákno.
- Každá změna statusu se loguje (`change_log`).

### 10.2 Soupisy práce
Samostatný workflow se stavy `draft → submitted → reviewed → ready_for_invoice → invoiced` včetně zpětných přechodů pro vedení/admin. Detail viz **§13.2**.

## 11. Offline režim a synchronizace
Offline režim je povinná funkce, protože pracovníci často pracují bez signálu.

Princip:
- lokální DB je zdroj pravdy pro zařízení
- server je zdroj pravdy pro firmu
- data se nejdříve ukládají lokálně
- poté vznikne outbox mutace
- aplikace zkusí automatický sync
- pokud není signál, data zůstávají lokálně
- po návratu online se data odešlou

UI musí ukazovat:
- online/offline stav
- počet čekajících záznamů
- počet čekajících fotek
- velké tlačítko Synchronizovat

## 12. Konflikty
Konflikty se nesmí automaticky přepisovat.

Řešit ve V1:
- duplicitní číslo ucpávky na stejném patře a stavbě
- offline editace entity, kterou mezitím změnil někdo jiný
- pokus o editaci zamčené ucpávky
- smazaná nebo archivovaná stavba

Chování:
- online duplicita se blokuje hned
- offline duplicita se uloží lokálně, ale při syncu vznikne konflikt
- konflikt vidí worker i vedení
- vedení/admin ručně rozhodne

## 13. Exporty, soupisy práce a ceník

V systému existují **dva související, ale oddělené moduly**:

### 13.1 Reporty (filtr-based export ucpávek)
Obrazovka **Soupis prací / Export** (`/reports`) – agregovaný export podle filtrů (stavba, období, pracovník, patro, status…).

- `GET /api/reports/work-summary` – náhled dat
- `GET /api/reports/export/pdf` – PDF
- `GET /api/reports/export/csv` – CSV (volitelné sloupce)

Worker vidí export **jen svých** záznamů (server-side scope). Vedení a admin vidí vše.

### 13.2 Soupisy práce (worksheet workflow) – implementováno 2026-06
Modul **Soupisy práce** (`/worksheets`) – formální soupis s workflow stavy, zamraženými položkami a auditem. Každý soupis patří jedné zakázce a obsahuje snapshot položek (`worksheet_items`).

**Stavy soupisu (`WorkSheetStatus`):**

| Stav | Kód | Význam |
|---|---|---|
| Rozpracovaný | `draft` | Lze doplňovat položky |
| Odevzdaný | `submitted` | Worker odevzdal k kontrole |
| Zkontrolovaný | `reviewed` | Schváleno vedením |
| Připravený k fakturaci | `ready_for_invoice` | Předáno účetní |
| Vyfakturovaný | `invoiced` | Uzavřeno |

**Povolené přechody (včetně zpětných pro vedení/admin):**
```
draft → submitted
submitted → reviewed | draft
reviewed → ready_for_invoice | submitted | draft
ready_for_invoice → invoiced | reviewed
invoiced → ready_for_invoice
```

**Práva ke změně stavu:**
- **worker** – pouze `draft → submitted`; po odevzdání zakázáno, dokud vedení nevrátí do `draft`
- **vedení / admin** – libovolný platný přechod včetně návratu zpět a fakturačních stavů

**Audit:** každá změna stavu → záznam v `change_log` (kdo, kdy, starý/nový stav, volitelný komentář) + `activity_log`.

**Detail soupisu (Flutter):** seznam → klepnutí → `/worksheets/:id` – zakázka, období, pracovníci, položky, celková hodnota (pokud existuje ceník), historie stavů, tlačítka PDF/CSV/stav.

**API soupisů:**
- `GET /api/worksheets` – seznam (worker jen přiřazené)
- `POST /api/worksheets` – vytvoření
- `GET /api/worksheets/:id` – detail + `statusHistory`, `totalValue`, `allowedStatusTargets`
- `POST /api/worksheets/:id/items` – přidání položek (jen `draft`)
- `POST /api/worksheets/:id/populate` – auto-vyplnění z ucpávek
- `PATCH /api/worksheets/:id/status` – `{ status, comment? }`
- `GET /api/worksheets/:id/export/pdf` – PDF daného soupisu
- `GET /api/worksheets/:id/export/csv` – CSV daného soupisu

**Práva k detailu a exportu:** stejná pravidla jako u `GET /api/worksheets/:id` – worker jen vlastní, ostatní role dle `worksheet.view` (403 na backendu, ne jen skrytí tlačítek).

**Uložené soupisy (Flutter):** vedení/admin vidí kořenové složky **Pro pracovníky**, **Pro zákazníka** a případně **Archiv**. Teprve uvnitř složky Pro pracovníky jsou jednotliví pracovníci; zákaznické soupisy nejsou zanořené pod pracovníkem.

### 13.3 Ceník – implementováno
Správa ceníku vedením/adminem, prohlížení všemi relevantními rolemi. Ceny se ukládají jako snapshot u položek soupisu a u záznamů ucpávek (`unitPrice`, `totalPrice`).

- `GET /api/price-list` – aktivní ceník
- `POST /api/price-list/seed` – seed výchozího ceníku (vedení/admin)

Obrazovka Flutter: `/price-list`.

### 13.4 Filtry reportů (beze změny)
- zakázka, pracovník, období, status, patro, typ prostupu, materiál, systém

## 14. Vyhledávání a statistiky
Worker:
- vyhledává pouze v otevřené zakázce
- filtry: patro, číslo ucpávky

Management/Admin:
- globální vyhledávání přes stavby, patra, ucpávky, pracovníky, materiály a statusy

Statistiky:
- počet ucpávek za den
- počet čekajících na kontrolu
- počet zkontrolovaných
- počet fakturovaných
- výkon pracovníků
- nejčastější typy prostupů

## 15. Logování
Logování je povinné.

Logy:
- login log
- activity log
- change log
- status log
- sync log
- error log
- admin log

Auditní logy ukládat do databáze, technické chyby i do serverových logů.

Auditní obrazovka seskupuje hodnotné sekce: Ucpávky, Soupisy, Stavby a patra, Fotky/výkresy, Uživatelé/práva, Zálohy a Systém/sync. Mutace ukládají do metadata konkrétní kontext: číslo/název stavby, název patra, typ soupisu, pracovníky, počty položek a informace o výkresu/fotce.

Logovat:
- kdo provedl akci
- kdy
- na jaké entitě
- původní hodnotu
- novou hodnotu
- metadata

## 16. Archivace a mazání
Nikdy nemazat tvrdě v první verzi.

Zakázka se do archivu nepřesouvá sama. Archivaci provádí ručně vedení nebo admin.

Smazané položky se pouze označí jako smazané:
- deleted_at
- deleted_by
- delete_reason volitelně

Admin má možnost obnovy.

## 17. Doporučený technický stack
Frontend:
- Flutter
- Riverpod
- go_router
- Drift SQLite
- Dio
- flutter_image_compress

Backend:
- Node.js
- Express
- PostgreSQL
- Prisma
- Zod validace
- JWT/session tokeny
- Multer nebo ekvivalent pro upload fotek
- Pino logger

Důvod pro PostgreSQL místo serverového SQLite:
- více uživatelů
- lepší indexy
- lepší reporty
- robustnější sync
- lepší budoucí škálování

## 18. Databázový model
Hlavní tabulky:
- users, user_sessions
- jobs, job_floors
- seals, seal_entries, seal_entry_materials, seal_photos
- **worksheets, worksheet_workers, worksheet_items** – modul soupisů práce
- **price_list, price_list_items** – ceník
- sync_mutations
- activity_log, change_log, login_log, error_log

Kritický unikátní index:
- `job_id + floor_id + seal_number` musí být unikátní mezi nesmazanými ucpávkami
- `worksheet_id + seal_entry_id` – stejný prostup nelze v soupisu duplicitně

## 19. API bloky
Auth:
- POST /api/auth/login
- POST /api/auth/logout
- GET /api/auth/me
- POST /api/auth/change-pin

Jobs:
- GET /api/jobs, GET /api/jobs/my
- GET /api/jobs/by-number/:projectNumber
- POST /api/jobs, PATCH /api/jobs/:id, PATCH /api/jobs/:id/archive
- DELETE /api/jobs/:id (soft)

Floors:
- GET /api/jobs/:jobId/floors
- POST /api/jobs/:jobId/floors
- PATCH /api/floors/:id, DELETE /api/floors/:id

Seals:
- GET /api/seals/floors/:floorId/seals
- GET /api/seals/:id, GET /api/seals/:id/history
- POST /api/seals, PATCH /api/seals/:id
- PATCH /api/seals/:id/status, DELETE /api/seals/:id
- GET /api/seals/trash, PATCH /api/seals/:id/restore (admin)
- POST /api/seals/:id/photos

Photos:
- DELETE /api/photos/:id (zakázáno pro všechny role ve V1)

Sync:
- POST /api/sync/push
- GET /api/sync/pull

Reports (filtr-based):
- GET /api/reports/work-summary
- GET /api/reports/export/pdf
- GET /api/reports/export/csv

Worksheets (modul soupisů):
- GET /api/worksheets
- POST /api/worksheets
- GET /api/worksheets/:id
- POST /api/worksheets/:id/items
- POST /api/worksheets/:id/populate
- PATCH /api/worksheets/:id/status
- GET /api/worksheets/:id/export/pdf
- GET /api/worksheets/:id/export/csv

Price list:
- GET /api/price-list
- POST /api/price-list/seed

Users (vedení/admin):
- GET /api/users, POST /api/users, PATCH /api/users/:id

Stats:
- GET /api/stats/overview

Logs:
- GET /api/logs/activity (vedení/admin)

## 20. MVP rozsah
MVP V1 – stav implementace (2026-06):

| Oblast | Stav |
|---|---|
| login jméno + PIN | hotovo |
| role worker / vedeni / admin | hotovo |
| stavby přes 8místné číslo | hotovo |
| patra, správa staveb | hotovo |
| seznam ucpávek, formulář, materiály, presety rozměrů | hotovo |
| fotky (upload, retry, bez mazání workerem) | hotovo |
| offline ukládání + sync push/pull | hotovo |
| konflikty (duplicita, zamčené záznamy) | hotovo |
| statusy ucpávek (draft/checked/invoiced) | hotovo |
| reporty – filtr + CSV/PDF export | hotovo |
| **soupisy práce – workflow, detail, export, audit** | **hotovo** |
| **ceník – prohlížení + správa** | **hotovo** |
| správa uživatelů, statistiky, logy | hotovo |
| admin koš / obnova ucpávek | hotovo |
| Android debug APK (lokální test proti PC) | hotovo |
| Windows release build | hotovo |

Nechat na později:
- push notifikace, diskuze
- QR kódy, tisk štítků
- automatická fakturace / ERP napojení
- produkční HTTPS deploy (Railway) – konfigurace existuje, release APK vyžaduje `--dart-define=API_BASE_URL=...`

## 21. Roadmapa implementace
1.–25. základní bloky – **většina hotova** (viz `FRONTEND_STATUS.md`, `RUNNING.md`)
26. Soupisy práce – detail, export PDF/CSV, RBAC, audit stavů – **hotovo (2026-06)**
27. Lokální testování Android APK proti PC v LAN – **hotovo** (viz §26)
28. Produkční deploy (Railway) + release APK s HTTPS URL – **připraveno, ne povinné pro interní beta**
29. Testování a stabilizace – **probíhá**

## 22. Struktura tasků pro Cursor
Cursoru nedávat jeden obří task. Používat malé přesné tasky.

Správný formát tasku:
- cíl
- kontext
- přesný rozsah
- čeho se nesmí dotýkat
- očekávaný výstup
- testovací kroky

Příklad:
"Implementuj pouze Auth API v backendu. Nesahej na Flutter. Nepřidávej sync. Použij Prisma model User a UserSession. Přidej validaci přes Zod a testovací endpoint /api/auth/me."

## 23. Rizika projektu
Největší rizika:
- offline sync
- konflikty
- fotky
- špatný state management
- příliš velké tasky v Cursoru
- masivní refactory
- chybějící testování

Doporučení:
- commit po každé malé změně
- main branch držet stabilní
- dev branch pro rozdělané věci
- sync implementovat až po stabilním CRUD

## 24. Testovací checklist
Povinně otestovat:
- worker online vytvoří ucpávku
- worker offline vytvoří ucpávku
- data přežijí restart aplikace
- po návratu online proběhne sync
- fotka se nahraje později po selhání
- duplicitní číslo online je blokováno
- duplicitní číslo offline vytvoří konflikt
- zkontrolovanou ucpávku worker neupraví
- vedení vrátí ucpávku na rozpracováno
- fakturovaný záznam je zamčený
- worker nevidí admin/export funkce mimo scope
- admin obnoví smazaný záznam
- archivovaná stavba se workerovi nezobrazuje jako aktivní

**Soupisy práce (2026-06):**
- worker rozklikne a stáhne **jen vlastní** soupis; cizí → 403
- vedení/admin rozklikne, stáhne a změní stav libovolného soupisu včetně zpětného přechodu
- vedení/admin mění i fakturační stavy; worker mimo svůj scope → 403
- worker nemůže měnit stav po odevzdání (kromě nového odevzdání po vrácení do `draft`)
- každá změna stavu vytvoří záznam v historii (kdo, kdy, from→to, komentář)
- backend testy: `backend/__tests__/worksheets.integration.test.js`

**Android lokálně (viz §26):**
- backend běží na PC, telefon ve stejné Wi‑Fi
- `http://<IP_PC>:3000/health` dostupné z prohlížeče telefonu
- debug APK nainstalováno, login a soupisy fungují

## 25. Doporučený první prompt do Cursoru
Nezačínej implementací celé aplikace.

První prompt má být pouze analytický:

Analyzuj přiloženou projektovou dokumentaci. Nevytvářej zatím žádný kód. Navrhni detailní implementační plán po malých blocích pro backend, frontend, databázi, offline sync, fotky, reporty a testování. U každého bloku napiš závislosti, rizika a ověřovací kroky. Výstupem má být pouze plán, ne implementace.

## 26. Lokální testování Android (bez Railway/GitHub)
Pro interní test na fyzickém telefonu proti backendu na PC:

1. **Backend:** `cd backend && npm run dev` (PostgreSQL + seed, viz [RUNNING.md](../RUNNING.md))
2. **Síť:** telefon a PC ve **stejné Wi‑Fi**; ověř `http://<IP_PC>:3000/health` v prohlížeči telefonu
3. **Debug APK:** sestavení `flutter build apk --debug` – API URL pro debug je v `frontend/lib/core/config.dart` (`_debugLanApiBaseUrl`, aktuálně LAN IP PC)
4. **Instalace:** USB + `adb install -r build/app/outputs/flutter-apk/app-debug.apk`, nebo ruční kopie APK na telefon
5. **Nové APK** sestavovat jen po změně kódu nebo změně IP PC

Release APK pro produkci (Railway) používá jinou URL – `--dart-define=API_BASE_URL=https://…` (release default zůstává `localhost`, ne produkce).

