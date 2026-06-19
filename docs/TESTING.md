# Testovací checklist – Ucpávky V1

Viz také [04_TESTOVACI_CHECKLIST.md](04_TESTOVACI_CHECKLIST.md), [CI.md](CI.md) (GitHub Actions).

## CI (GitHub Actions)

Při push/PR do `main` běží workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

1. **backend** – PostgreSQL service, `npm test` (52 integrační testů)
2. **flutter-unit** – `flutter analyze` + offline/sync unit testy (bez API)
3. **flutter-runtime** – backend na `:3000` + `runtime_verification_test.dart` + `login_home_smoke_test.dart`

Podrobnosti: [CI.md](CI.md).

## Automatické testy

### Backend (Jest + supertest)

Integrační smoke testy používají **oddělenou databázi `ucpavky_test`**, ne vývojovou `ucpavky`.

#### 1. Vytvoření test DB (jednorázově)

```powershell
# pgAdmin Query Tool nebo psql jako postgres:
# Soubor: docs/setup-local-postgres-test.sql
```

Výchozí URL:

```text
postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky_test
```

Volitelně vlastní URL:

```powershell
$env:TEST_DATABASE_URL = "postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky_test"
```

#### 2. Spuštění testů

```powershell
cd c:\Users\vojte\Desktop\unifast\backend
npm install
npm test
```

Pouze smoke integrace:

```powershell
npm run test:integration
```

**Co testy dělají:**

- `globalSetup`: `prisma migrate deploy` + `prisma db seed` na `ucpavky_test`
- `api.smoke.integration.test.js`: supertest proti `createApp()` (bez spuštěného serveru)
- Pokrytí: `GET /health`, `POST /api/auth/login`, `GET /api/jobs`, `GET /api/jobs/by-number/12345678`, `GET /api/jobs/:jobId/floors`
- Unit testy: `seal.service.test.js` (business rules kopie)

**Předpoklady:** PostgreSQL běží na `localhost:5432`, role `ucpavky` existuje.

Pokud role `ucpavky` nemá právo `CREATEDB`, vytvořte DB ručně (`docs/setup-local-postgres-test.sql`) nebo nastavte superuser URL:

```powershell
$env:POSTGRES_ADMIN_URL = "postgresql://postgres:VASE_HESLO@localhost:5432/postgres"
npm test
```

### Frontend

**Unit/offline (bez běžícího backendu):**

```powershell
cd c:\Users\vojte\Desktop\unifast\frontend
flutter analyze
flutter test test/seal_list_offline_test.dart test/floor_list_offline_test.dart test/sync_conflict_test.dart test/seal_detail_offline_test.dart test/sync_retry_test.dart test/widget_test.dart
```

**Runtime (vyžaduje backend na `:3000`):**

```powershell
flutter test test/integration/runtime_verification_test.dart test/login_home_smoke_test.dart
```

## Manuální scénáře (po spuštění DB + backend + frontend)

### Auth
- [ ] Login worker1 / PIN 123456
- [ ] Špatný PIN → chyba
- [ ] Worker nemá položky Správa / Export v menu

### Worker flow
- [ ] Stavba 12345678 → patra → seznam ucpávek
- [ ] Nová ucpávka s chipy, 2 prostupy, fotka
- [ ] Po uložení dialog Přidat další / Zpět

### Offline
- [ ] Vypnout síť → vytvořit ucpávku → data v Sync obrazovce pending
- [ ] Zapnout síť → Synchronizovat

### Management
- [ ] vedeni / 1234 → změna statusu ucpávky
- [ ] Export soupisu prací

## Spuštění prostředí

Primární postup (lokální PostgreSQL bez Dockeru): viz [RUNNING.md](../RUNNING.md).

```powershell
cd c:\Users\vojte\Desktop\unifast\backend
npx prisma migrate deploy
npx prisma db seed
npm run dev
```

```powershell
cd c:\Users\vojte\Desktop\unifast\frontend
flutter run -d windows --debug
```
