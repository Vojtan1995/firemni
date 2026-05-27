# KNOWN_ISSUES.md – známé problémy a omezení

## 1. PostgreSQL není spuštěný → Prisma chyby (P1001)

- **Projev:** `npx prisma migrate deploy`, `npx prisma db seed`, login na `/api/auth/login` končí:

  ```text
  P1001: Can't reach database server at `localhost:5432`
  ```

- **Příčina:** PostgreSQL služba ve Windows neběží, nebo `DATABASE_URL` neodpovídá reálným přihlašovacím údajům.
- **Oprava:** postup v [`RUNNING.md`](RUNNING.md) sekce 1 (lokální PostgreSQL bez Dockeru):
  1. nainstalovat/spustit PostgreSQL,
  2. vytvořit DB `ucpavky` (`docs/setup-local-postgres.sql`),
  3. zkontrolovat `backend/.env`,
  4. `npx prisma migrate deploy` + `npx prisma db seed`.

## 2. Docker je volitelný (aktuálně se nepoužívá)

- **Stav:** Docker Desktop na tomto PC stabilně nenabíhá (engine API vrací HTTP 500).
- **Dopad:** `docker compose up` není podporovaná cesta pro lokální vývoj na tomto stroji.
- **Náhrada:** lokální PostgreSQL instalace ve Windows (primární postup v `RUNNING.md`).
- **Poznámka:** `docker-compose.yml` zůstává v repu pro jiné stroje/CI, ale není povinný.

## 3. Login vrací 500, když DB není připravená

- **Projev:** `POST /api/auth/login` → `{"error":"Interní chyba serveru","code":"INTERNAL_ERROR"}` a v logu backendu Prisma P1001.
- **Příčina:** backend běží, ale databáze není dostupná nebo není seednutá.
- **Oprava:** dokončit kroky z bodu 1; `/health` může fungovat i bez DB, login vyžaduje funkční PostgreSQL.

## 4. Flutter build Windows – toolchain

- **Projev:** `flutter build windows` může skončit `MSBUILD : error MSB1009`.
- **Příčina:** chybí Visual Studio Build Tools / CMake / Windows SDK.
- **Oprava:** doinstalovat desktop C++ workload, pak `flutter doctor` a znovu build.

## 5. Flutter build APK – varování pluginů

- **Projev:** varování Kotlin Gradle Plugin u některých pluginů.
- **Dopad:** build APK obvykle proběhne úspěšně; není to blokér backend runtime.
