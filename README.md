# Ucpávky – evidence požárních ucpávek (V1)

Interní firemní aplikace pro evidenci požárních ucpávek a prostupů.

## Stack

- **Backend:** Node.js 20+, Express 4, Prisma 6, PostgreSQL 16
- **Frontend:** Flutter 3.44+, Riverpod, go_router, Drift (SQLite), Dio

## Git workflow

- `main` – stabilní větev
- `dev` – vývojová větev
- Commit po každém dokončeném bloku

## Rychlý start

### 1. Databáze

```bash
docker compose up -d
```

Nebo lokální PostgreSQL – viz [RUNNING.md](RUNNING.md).

### 2. Backend

```bash
cd backend
cp ../.env.example .env
npm install
npx prisma migrate deploy
npx prisma db seed
npm run dev
```

API běží na `http://localhost:3000`. Health: `GET /health`, `GET /ready`.

### 3. Frontend

```bash
cd frontend
flutter pub get
flutter run -d windows
# nebo: flutter run -d android
```

V debug režimu se použije LAN adresa z `lib/core/config.dart` (nebo `--dart-define=API_BASE_URL=...`).

## Release build (Android)

Release APK **vyžaduje**:

1. **`API_BASE_URL`** – URL produkčního backendu
2. **`android/key.properties`** – podpisový keystore (viz `frontend/android/key.properties.example`)

```bash
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

Bez `API_BASE_URL` release build spadne při startu aplikace.

### Aktualizace Android klienta (bez ručního šíření APK)

Po nahrání nového APK na HTTPS nastavte na backendu env `APP_RELEASE_*` (viz [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) §5b). Aplikace při startu zavolá `GET /api/app/release?platform=android` a nabídne stažení.

```powershell
.\build-release.ps1 -ApiUrl https://your-backend.example.com
# skript na konci vypíše doporučené APP_RELEASE_* hodnoty z pubspec.yaml
```

## Produkční backend (Railway)

Minimální proměnné prostředí:

| Proměnná | Poznámka |
|----------|----------|
| `NODE_ENV=production` | |
| `JWT_SECRET` | silný náhodný řetězec |
| `DATABASE_URL` | PostgreSQL |
| `CORS_ORIGIN` | URL frontendu / APK |
| `PUBLIC_UPLOADS=false` | fotky jen přes auth API |
| `STORAGE_DRIVER=s3` | perzistentní fotky na Railway |
| `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_ENDPOINT` | object storage |

Podrobnosti: [docs/DEPLOY_RAILWAY.md](docs/DEPLOY_RAILWAY.md), R2 overeni a backfill: [docs/R2_STORAGE_RUNBOOK.md](docs/R2_STORAGE_RUNBOOK.md).

Lokální vývoj používá `STORAGE_DRIVER=local` (default) a `UPLOAD_PATH=./uploads`.

## Seed účty

PIN v dev prostředí je **`123456`** (6 číslic). Validace přijímá 6–8 číslic.

V produkci nastavte `SEED_DEMO_PIN` před `npx prisma db seed`.

| Uživatel | Role | Popis |
|----------|------|-------|
| admin | admin | Plný přístup, správa všech uživatelů, koš, zálohy |
| vedeni | vedení | Správa staveb a pater, export, ceník, pracovní listy, správa uživatelů (mimo admin) |
| worker1, worker2 | worker | Tvorba ucpávek, offline sync, fotky |

## Testovací stavba

Číslo stavby: `12345678`

## Testy

```bash
cd backend && npm test          # 52 integračních testů (Jest + supertest)
cd frontend && flutter test     # offline unit testy
```

## API endpointy – přehled

| Skupina | Endpointy |
|---------|-----------|
| Auth | `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`, `POST /api/auth/change-pin` |
| Stavby | `GET|POST /api/jobs`, `GET /api/jobs/by-number/:number`, `PATCH /api/jobs/:id/archive\|complete\|activate` |
| Patra | `GET|POST /api/jobs/:jobId/floors`, `GET|POST /api/jobs/:jobId/floors/:floorId/drawing` |
| Ucpávky | `GET|POST /api/seals`, `PATCH /api/seals/:id/status\|review\|restore`, `DELETE /api/seals/:id` |
| Bulk operace | `POST /api/seals/bulk-status`, `POST /api/seals/bulk-move`, `POST /api/seals/bulk-export/csv` |
| Fotky | `POST /api/seals/:id/photos`, `GET /api/photos/:id/file` |
| Sync | `POST /api/sync/push`, `GET /api/sync/pull` |
| Sestavy | `GET /api/reports/work-summary`, `GET /api/reports/export/csv\|pdf` |
| Pracovní listy | `GET|POST /api/worksheets`, `GET /api/worksheets/:id/export/csv\|pdf` |
| Zprávy | `GET /api/messages`, `POST /api/messages`, `PATCH /api/messages/:id/read` |
| Notifikace | `GET /api/notifications`, `PATCH /api/notifications/read-all` |
| Statistiky | `GET /api/stats/overview` |
| Vyhledávání | `GET /api/search?q=...` |
| Ceník | `GET /api/price-list`, `POST /api/price-list/publish` |
| Logy | `GET /api/activity`, `GET /api/changes` |
| Admin | `GET /api/seals/trash`, `GET /api/admin/backup-status`, `GET|POST /api/admin/backups` |
| Interní provoz | `POST /api/internal/backup-runs` (GitHub Actions report DB/object/restore běhů) |
| App update | `GET /api/app/release?platform=android` |

Podrobné schéma DB: [docs/DATABASE.md](docs/DATABASE.md). Sync protokol: [docs/SYNC.md](docs/SYNC.md).

## Funkce (od v1.0.0)

### Pracovní listy (Worksheets)
Workflow fakturace: `draft → submitted → reviewed → ready_for_invoice → invoiced`. Umožňují přiřadit ucpávky z různých pater do jednoho listu pro účetní zpracování. Export do CSV/PDF.

### Zprávy a notifikace
Interní přímé zprávy mezi uživateli (`/api/messages`). Systémové notifikace při stavových změnách ucpávek (`/api/notifications`).

### Statistiky / Dashboard
`GET /api/stats/overview` vrací přehled stavu ucpávek podle role. Management a admin vidí celkové statistiky, worker vidí jen vlastní.

### Globální vyhledávání
`GET /api/search?q=...` prohledává ucpávky, stavby a pracovníky najednou. Lze filtrovat `jobId`, `floorId`.

### Ceník s verzováním
Pricing modul s historií verzí. Vedení a admin mohou publikovat nové verze, reporty vždy počítají s verzí platnou v době vytvoření ucpávky.

### Plány pater (Floor drawings)
Upload PNG/JPG plánu ke každému patru. Ucpávky lze umístit jako markery na plán (normalizované souřadnice x/y).

### Bulk operace
Hromadná změna statusu, přesun ucpávek mezi patry, hromadný CSV export – vše přes `/api/seals/bulk-*` endpointy.

### Správa účastníků stavby
Vedení může přiřadit konkrétní pracovníky ke stavbě (`/api/jobs/:jobId/participants`). Pracovníci vidí jen stavby, na které jsou přiřazeni.

### Změna PINu
`POST /api/auth/change-pin` – ověří starý PIN a nastaví nový. Nový PIN musí mít 6–8 číslic.

## Dokumentace

| Soubor | Obsah |
|--------|--------|
| [RUNNING.md](RUNNING.md) | Lokální spuštění (PostgreSQL, backend, Flutter) |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | Známé problémy a obejití |
| [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) | Checklist pro beta a produkci |
| [AUDIT_REPORT_NASAZENI.md](AUDIT_REPORT_NASAZENI.md) | Audit připravenosti k nasazení |
| [docs/DEPLOY_RAILWAY.md](docs/DEPLOY_RAILWAY.md) | Deploy backendu na Railway |
| [docs/DATABASE.md](docs/DATABASE.md) | Schéma DB, tabulky, enums, pravidla |
| [docs/SYNC.md](docs/SYNC.md) | Offline-first sync protokol |
| [docs/TESTING.md](docs/TESTING.md) | Testovací strategie |
| [docs/CI.md](docs/CI.md) | GitHub Actions pipeline |
| [docs/01_KOMPLETNI_SPECIFIKACE.md](docs/01_KOMPLETNI_SPECIFIKACE.md) | Plná specifikace (cs) |
