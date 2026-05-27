# Testovací checklist – Ucpávky V1

Viz také [04_TESTOVACI_CHECKLIST.md](04_TESTOVACI_CHECKLIST.md).

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

```powershell
cd c:\Users\vojte\Desktop\unifast\frontend
flutter test test/integration/runtime_verification_test.dart
```

## Manuální scénáře (po spuštění DB + backend + frontend)

### Auth
- [ ] Login worker1 / PIN 1234
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
