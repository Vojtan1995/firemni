
# Implementační roadmapa

## Fáze 0 - Příprava
- založit repozitář
- nastavit Git větve main/dev
- vložit dokumentaci do složky /docs
- nastavit README

## Fáze 1 - Skeleton
- backend složka
- frontend složka
- shared docs
- env příklady
- docker-compose pro PostgreSQL

## Fáze 2 - Databáze
- Prisma setup
- schema.prisma
- migrace
- seed admin účtu

## Fáze 3 - Backend základ
- Express setup
- logger
- error middleware
- auth middleware
- role middleware

## Fáze 4 - Auth
- login jméno + PIN
- hash PINu
- session token
- /me endpoint
- login log

## Fáze 5 - Stavby a patra
- jobs CRUD
- floors CRUD
- otevření stavby přes 8místné číslo
- archivace

## Fáze 6 - Ucpávky
- seals CRUD
- entries
- materials
- statusy
- soft delete

## Fáze 7 - Fotky
- upload
- metadata
- komprese na klientovi
- retry upload

## Fáze 8 - Flutter základ
- Riverpod
- go_router
- theme
- login
- hlavní menu

## Fáze 9 - Worker flow
- zadání čísla stavby
- výběr patra
- seznam ucpávek
- formulář

## Fáze 10 - Offline
- Drift SQLite
- lokální tabulky
- outbox queue
- lokální uložení formuláře

## Fáze 11 - Sync
- push
- pull
- mutationId idempotence
- konflikty
- retry

## Fáze 12 - Management
- kontrola ucpávek
- statusy
- exporty
- logy

## Fáze 13 - Testování
- offline scénáře
- konflikty
- fotky
- role
- exporty
