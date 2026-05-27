
# Struktura tasků pro Cursor

## Pravidla
- Jeden task = jedna malá oblast.
- Agent mód pouze na přesně definované úkoly.
- Před větší změnou použít Plan.
- Na otázky a návrhy používat Ask.
- Po každém tasku test a commit.

## Task 01 - Analýza dokumentace
Cíl: Cursor pouze analyzuje dokumentaci a navrhne plán. Bez kódu.

Prompt:
Analyzuj dokumentaci ve složce /docs. Nevytvářej žádný kód. Navrhni implementační plán po malých blocích, uveď závislosti, rizika a testovací kroky.

## Task 02 - Skeleton projektu
Cíl: vytvořit strukturu, ne business logiku.

Prompt:
Vytvoř základní strukturu monorepo projektu s backendem Node.js/Express a frontendem Flutter. Neimplementuj žádnou business logiku, sync ani formuláře. Přidej pouze základní složky, README, env příklady a gitignore.

## Task 03 - Prisma schema
Cíl: vytvořit DB modely.

Prompt:
Implementuj Prisma schema podle docs/DATABASE.md. Přidej modely users, sessions, jobs, job_floors, seals, seal_entries, seal_entry_materials, seal_photos, sync_mutations a log tabulky. Nesahej na frontend.

## Task 04 - Auth API
Cíl: login jménem + PIN.

Prompt:
Implementuj pouze Auth API: login, logout, me. Použij hash PINu, session tokeny, login log a role. Nesahej na jobs, seals, sync ani Flutter.

## Task 05 - Jobs + Floors API
Cíl: stavby a patra.

Prompt:
Implementuj API pro stavby a patra. Worker může otevřít stavbu podle 8místného čísla. Patra zakládá pouze management/admin. Přidej role checks a activity log.

## Task 06 - Seals API
Cíl: ucpávky a prostupy.

Prompt:
Implementuj CRUD pro seals, seal_entries a seal_entry_materials. Worker může editovat pouze rozpracované. Management/admin může měnit status. Přidej soft delete a change log.

## Task 07 - Photos API
Cíl: upload fotek.

Prompt:
Implementuj upload fotek k ucpávce. Ukládej metadata do DB a soubory mimo DB. Worker nesmí mazat fotky. Přidej logování uploadu.

## Task 08 - Flutter skeleton
Cíl: základ UI bez syncu.

Prompt:
Vytvoř Flutter skeleton s Riverpod, go_router, tématem, login screenem a hlavním menu podle role. Nepřidávej offline sync.

## Task 09 - Worker screens
Cíl: hlavní flow workerů.

Prompt:
Implementuj obrazovky: zadání čísla stavby, výběr patra, seznam ucpávek a detail. Použij API, zatím bez offline režimu.

## Task 10 - Seal form UI
Cíl: rychlý formulář.

Prompt:
Implementuj formulář ucpávky s chipy/tlačítky místo dropdownů. Podporuj více prostupů a více materiálů na prostup. Neimplementuj sync.

## Task 11 - Local DB
Cíl: lokální ukládání.

Prompt:
Přidej Drift SQLite lokální databázi pro cache staveb, pater, ucpávek, prostupů, materiálů, fotek a outbox queue. Neimplementuj server sync.

## Task 12 - Sync push/pull
Cíl: synchronizace.

Prompt:
Implementuj sync push/pull podle docs/SYNC.md. Použij mutationId pro idempotenci. Řeš konflikty duplicity čísla a verze entity. Nepřidávej reporty.

## Task 13 - Reports
Cíl: soupis prací.

Prompt:
Implementuj work summary report s filtry: zakázka, období, pracovník, status, patro, typ, materiál. Přidej CSV export. PDF až samostatně.

## Task 14 - Logs UI
Cíl: audit.

Prompt:
Implementuj obrazovku logů pro management/admin s filtrováním podle typu akce, uživatele, entity a období.
