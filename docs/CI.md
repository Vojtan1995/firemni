# CI – GitHub Actions (DOC-01)

Automatické ověření při **push** a **pull request** do větví `main` / `master`.

Workflow: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

**Nepoužívá:** Docker Desktop, lokální secrets v repozitáři, produkční `.env`.

---

## Jobs

| Job | Co dělá | Potřebuje běžící backend? |
|-----|---------|----------------------------|
| **backend** | PostgreSQL 16 service → `npm ci` → `prisma generate` → `npm test` (migrate + seed v `globalSetup`) | Ne (supertest přes `createApp()`) |
| **flutter-unit** | `flutter analyze` + offline/sync unit testy | Ne |
| **flutter-runtime** | PostgreSQL + `npm start` na `:3000` → runtime + login E2E testy | Ano |

`flutter-runtime` běží až po úspěšném **backend** (`needs: backend`).

---

## PostgreSQL v CI

Service kontejner `postgres:16`:

- user: `ucpavky`
- password: `ucpavky_dev`
- databáze: `ucpavky_test`

Proměnné (stejné jako lokální testy):

```text
TEST_DATABASE_URL=postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky_test
POSTGRES_ADMIN_URL=postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky_test
```

`POSTGRES_ADMIN_URL` ukazuje na existující `ucpavky_test` (service ji vytvoří při startu), takže `ensureTestDatabase` v Jest setupu jen ověří existenci DB – bez superuser `postgres` role.

---

## Flutter testy

### Bez backendu (`flutter-unit`)

```text
test/seal_list_offline_test.dart
test/floor_list_offline_test.dart
test/sync_conflict_test.dart
test/seal_detail_offline_test.dart
test/sync_retry_test.dart
test/widget_test.dart
```

### S backendem (`flutter-runtime`)

Po `prisma migrate deploy`, `db seed` a `npm start`:

```text
test/integration/runtime_verification_test.dart
test/login_home_smoke_test.dart
```

API URL: `--dart-define=API_BASE_URL=http://localhost:3000` (výchozí stejné jako lokálně).

---

## Lokální ekvivalent

```powershell
# Backend (PostgreSQL musí běžet)
cd backend
npm test

# Flutter bez sítě
cd ..\frontend
flutter analyze
flutter test test/seal_list_offline_test.dart test/floor_list_offline_test.dart test/sync_conflict_test.dart test/seal_detail_offline_test.dart test/sync_retry_test.dart test/widget_test.dart

# Flutter runtime (backend npm run dev na :3000)
flutter test test/integration/runtime_verification_test.dart test/login_home_smoke_test.dart
```

---

## Co CI záměrně neřeší

- Windows / Android release build (PLAT-01, PLAT-02)
- Manuální checklist z [04_TESTOVACI_CHECKLIST.md](04_TESTOVACI_CHECKLIST.md)
- Produkční deploy ani secrets (JWT v runtime jobu je pouze testovací hodnota v runneru)

---

## Řešení problémů

| Problém | Možná příčina |
|---------|----------------|
| Backend job: DB connection refused | Postgres service ještě není healthy – zkontrolujte health-cmd v workflow |
| `flutter-runtime`: Backend did not become ready | `npm start` selhal – v logu jobu hledejte chybu Prisma / port 3000 |
| Drift / SQLite na Linuxu | Job instaluje `libsqlite3-dev` |
| Login E2E fail | Seed musí obsahovat `worker1` / PIN `1234` – stejný seed jako lokálně |

Více o test DB: [TESTING.md](TESTING.md), [setup-local-postgres-test.sql](setup-local-postgres-test.sql).
