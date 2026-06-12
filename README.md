# Ucpávky – evidence požárních ucpávek (V1)

Interní firemní aplikace pro evidenci požárních ucpávek a prostupů.

## Stack

- **Backend:** Node.js, Express, Prisma, PostgreSQL
- **Frontend:** Flutter, Riverpod, go_router, Drift, Dio

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

Podrobnosti: [docs/DEPLOY_RAILWAY.md](docs/DEPLOY_RAILWAY.md).

Lokální vývoj používá `STORAGE_DRIVER=local` (default) a `UPLOAD_PATH=./uploads`.

## Seed účty (PIN: 1234 v dev)

| Uživatel | Role |
|----------|------|
| admin | admin |
| vedeni | vedení |
| ucetni | administrativa |
| worker1, worker2 | worker |

V produkci nastavte `SEED_DEMO_PIN` před `npx prisma db seed`.

## Testovací stavba

Číslo stavby: `12345678`

## Testy

```bash
cd backend && npm test
cd frontend && flutter test
```

## Dokumentace

| Soubor | Obsah |
|--------|--------|
| [RUNNING.md](RUNNING.md) | Lokální spuštění |
| [docs/DEPLOY_RAILWAY.md](docs/DEPLOY_RAILWAY.md) | Deploy backendu |
| [docs/TESTING.md](docs/TESTING.md) | Testovací strategie |
| [docs/CI.md](docs/CI.md) | GitHub Actions |
| [docs/](docs/) | Specifikace, roadmapa |
