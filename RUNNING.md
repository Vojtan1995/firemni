# RUNNING.md – Lokální spuštění Ucpávky V1

Tento návod předpokládá:
- **Node.js** 18+,
- **PostgreSQL nainstalovaný přímo ve Windows** (doporučená varianta),
- volitelně Flutter pro klienta.

> **Docker není potřeba.** `docker-compose.yml` zůstává v repozitáři jen jako volitelná alternativa.

---

## 1. PostgreSQL ve Windows (bez Dockeru)

### 1.1 Instalace PostgreSQL

1. Stáhněte instalátor z [https://www.postgresql.org/download/windows/](https://www.postgresql.org/download/windows/) (EDB installer).
2. Při instalaci:
   - port: **5432** (výchozí),
   - zapněte **pgAdmin 4** (volitelné, ale užitečné),
   - zapamatujte si heslo superuživatele `postgres`.
3. Po instalaci ověřte službu ve Windows:
   - `Win + R` → `services.msc`
   - služba typu `postgresql-x64-16` (číslo verze se může lišit) musí být **Running**.

### 1.2 Vytvoření uživatele a databáze `ucpavky`

#### Varianta A – SQL skript (doporučeno)

Soubor: [`docs/setup-local-postgres.sql`](docs/setup-local-postgres.sql)

**pgAdmin:**
1. Otevřete pgAdmin → připojení k lokálnímu serveru.
2. Query Tool → vložte obsah `docs/setup-local-postgres.sql` → Execute.

**psql (PowerShell):**

```powershell
# Upravte cestu podle vaší verze PostgreSQL, např. 16:
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres -f "c:\Users\vojte\Desktop\unifast\docs\setup-local-postgres.sql"
```

#### Varianta B – ruční SQL příkazy

Připojte se jako `postgres` a spusťte:

```sql
CREATE ROLE ucpavky WITH LOGIN PASSWORD 'ucpavky_dev';
CREATE DATABASE ucpavky OWNER ucpavky;
GRANT ALL PRIVILEGES ON DATABASE ucpavky TO ucpavky;
```

#### Varianta C – vlastní postgres účet

Pokud nechcete vytvářet roli `ucpavky`, stačí databáze a upravit `DATABASE_URL`, např.:

```env
DATABASE_URL=postgresql://postgres:VASE_HESLO@localhost:5432/ucpavky
```

### 1.3 Ověření, že DB běží

```powershell
Test-NetConnection -ComputerName localhost -Port 5432
```

`TcpTestSucceeded` musí být `True`.

Volitelně:

```powershell
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -U ucpavky -d ucpavky -h localhost -p 5432 -c "SELECT 1;"
```

---

## 2. Backend konfigurace (`.env`)

### 2.1 Vytvoření `backend/.env`

```powershell
cd c:\Users\vojte\Desktop\unifast\backend
copy ..\.env.example .env
```

### 2.2 Kontrola `DATABASE_URL`

Výchozí hodnota v `.env.example`:

```env
DATABASE_URL=postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky
```

Musí odpovídat vašemu lokálnímu PostgreSQL (uživatel, heslo, host, port, název DB).

---

## 3. Backend – migrace, seed, runtime

Adresář: `c:\Users\vojte\Desktop\unifast\backend`

### 3.1 Instalace závislostí

```powershell
cd c:\Users\vojte\Desktop\unifast\backend
npm install
```

### 3.2 Prisma migrace

```powershell
npx prisma migrate deploy
```

Očekávaný výstup: migrace `20250527000000_init` aplikována bez chyby.

### 3.3 Seed dat

```powershell
npx prisma db seed
```

Očekávaný výstup: `Seed OK` s testovací stavbou.

Seed vytvoří:
| Uživatel | PIN | Role |
|----------|-----|------|
| admin | 1234 | admin |
| vedeni | 1234 | management |
| worker1 | 1234 | worker |
| worker2 | 1234 | worker |

Testovací stavba: **12345678** (2 patra).

### 3.4 Spuštění backendu

```powershell
npm run dev
```

Server: `http://localhost:3000`

### 3.5 Ověření `/health`

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:3000/health
```

Očekáváno: HTTP 200, tělo obsahuje `"status":"ok"`.

### 3.6 Ověření login endpointu

```powershell
Invoke-WebRequest -UseBasicParsing -Method POST `
  -Uri http://localhost:3000/api/auth/login `
  -ContentType "application/json" `
  -Body '{"username":"worker1","pin":"1234"}'
```

Očekáváno: HTTP 200, JSON s `token` a `user.role = worker`.  
**Nesmí** se objevit Prisma `P1001`.

---

## 4. Volitelně: Docker Compose

Pouze pokud máte funkční Docker Desktop. Na tomto stroji Docker aktuálně není spolehlivý.

```powershell
cd c:\Users\vojte\Desktop\unifast
docker compose up -d
```

`DATABASE_URL` zůstává stejné (`localhost:5432`).

---

## 5. Flutter (stručně)

Adresář: `c:\Users\vojte\Desktop\unifast\frontend`

```powershell
flutter pub get
flutter run -d windows
```

API URL: `lib/core/config.dart` → `http://localhost:3000`

---

## 6. Rychlý checklist backend runtime

- [ ] PostgreSQL služba běží (`localhost:5432`)
- [ ] existuje DB `ucpavky` a uživatel odpovídá `DATABASE_URL`
- [ ] `npx prisma migrate deploy` OK
- [ ] `npx prisma db seed` OK
- [ ] `npm run dev` běží
- [ ] `GET /health` → 200
- [ ] `POST /api/auth/login` → 200 + token
