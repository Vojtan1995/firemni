# DEPLOY_RAILWAY.md

Minimální postup pro nasazení backendu na Railway pro demo/beta provoz.

## Aktualni produkcni storage pravidlo

Produkce nesmi bezet na lokalnim `UPLOAD_PATH` na Railway. Backend pri
`NODE_ENV=production` fail-fast vyzaduje:

```env
STORAGE_DRIVER=s3
PUBLIC_UPLOADS=false
S3_BUCKET=<r2-bucket-name>
S3_ACCESS_KEY_ID=<r2-access-key-id>
S3_SECRET_ACCESS_KEY=<r2-secret-access-key>
S3_ENDPOINT=https://<cloudflare-account-id>.r2.cloudflarestorage.com
S3_REGION=auto
S3_FORCE_PATH_STYLE=true
S3_KEY_PREFIX=photos
VERIFY_STORAGE_ON_START=true
```

Pred redeployem overte R2 prikazem `npm run storage:verify -- --env=../.env.local`.
Pri startu produkcniho backendu se stejny write/read/delete check spusti automaticky.
Po redeployi musi `GET /ready` vracet `storage.driver = "s3"` a
`storage.publicUploads = false`. Admin musi overit i
`POST /api/admin/storage/verify`, ktery provede live write/read/delete test
aktualni storage vrstvy. Backfill a audit jsou popsane v
[R2_STORAGE_RUNBOOK.md](R2_STORAGE_RUNBOOK.md).

## Scope
- Pouze deploy/config změny.
- Bez změn business logiky.
- Bez změn API kontraktů.
- Bez změn Flutter UI.

## 1) Co je v projektu připraveno
- Backend používá `PORT` z env v `backend/src/config.ts`.
- Backend používá `DATABASE_URL` z env v `backend/src/config.ts`.
- Produkční skripty jsou v `backend/package.json`:
  - `build`
  - `start`
  - `prisma:migrate:deploy`
  - `prisma:seed`
- Railway konfigurace build/start/health je v `backend/railway.toml`.

## 2) Railway služby
Vytvořte jeden Railway project se dvěma službami:
1. `backend` (Node service)
2. `Postgres` (Railway PostgreSQL)

## 3) Nastavení backend service

### Root directory
- Nastavte service root na `backend`.

### Variables
Nastavte:
- `NODE_ENV=production`
- `DATABASE_URL=${{Postgres.DATABASE_URL}}`
- `JWT_SECRET=<silny_secret>` (vytvořit v Railway ručně)
- `CORS_ORIGIN=https://<frontend-nebo-app-domain>` pro ostrý provoz whitelist
- `PUBLIC_UPLOADS=false`
- `UPLOAD_PATH` nenastavujte pro produkci; local storage je jen pro vyvoj nebo nouzovy override

### Perzistentní fotky a výkresy (povinné pro produkci)
Railway filesystem není perzistentní. Pro ostrý provoz nastavte S3-kompatibilní bucket (Railway Object Storage, Cloudflare R2, AWS S3, MinIO):

- `STORAGE_DRIVER=s3`
- `S3_BUCKET=<název bucketu>`
- `S3_ACCESS_KEY_ID=<access key>`
- `S3_SECRET_ACCESS_KEY=<secret>`
- `S3_REGION=auto` (nebo region poskytovatele)
- `S3_ENDPOINT=https://<endpoint>` (u Railway/R2/MinIO povinné)
- `S3_KEY_PREFIX=photos` (volitelný prefix klíčů)
- `S3_FORCE_PATH_STYLE=true` (u některých providerů nutné)

Pro Cloudflare R2 použijte S3 API access key pair, ne obecný Cloudflare API token.
Detailni postup overeni, auditu a backfillu je v [R2_STORAGE_RUNBOOK.md](R2_STORAGE_RUNBOOK.md).

Při `STORAGE_DRIVER=s3`:
- soubory přežijí restart/redeploy,
- stažení fotek probíhá přes autentizované `GET /api/photos/:id/file` (`PUBLIC_UPLOADS=false`).

Při `STORAGE_DRIVER=local` (default pro vývoj):
- `UPLOAD_PATH=./uploads` ukládá na disk instance (vhodné jen lokálně / demo).

Pro uzavrenou demo betu lze docasne pouzit `CORS_ORIGIN=*`, ale jen pokud je v Railway explicitne nastaveno `ALLOW_WILDCARD_CORS=true`.

Poznámka:
- `PORT` dodává Railway automaticky.

## 4) Build/start/migrate/seed

- Build: `npm ci && npx prisma generate && npm run build`
- Start: `npx prisma migrate deploy && npm run start`
- Migrace: Railway je spousti pred startem; rucne lze pouzit `npx prisma migrate deploy` (nebo `npm run prisma:migrate:deploy`)
- Seed (volitelně demo data): `npx prisma db seed` (nebo `npm run prisma:seed`)

## 5) Ruční nasazení krok za krokem
1. Připojte repozitář do Railway.
2. Vytvořte `backend` service se rootem `backend`.
3. Přidejte PostgreSQL service.
4. Nastavte variables dle sekce 3.
5. Spusťte deploy.
6. Migrace probehnou automaticky pred startem backendu podle `backend/railway.toml`.
7. Volitelně spusťte seed:
   - `npx prisma db seed`
8. Ověřte:
   - `GET https://<backend-domain>/health`
   - `GET https://<backend-domain>/ready`
   - `POST https://<backend-domain>/api/admin/storage/verify` s admin bearer tokenem
   - `POST https://<backend-domain>/api/auth/login`

## 6) Android APK na veřejnou URL
Po nasazení backendu sestavte APK:

`flutter build apk --release --dart-define=API_BASE_URL=https://<backend-domain>`

## 7) Uploady a úložiště fotek

| Režim | Env | Použití |
|-------|-----|---------|
| **local** (default) | `STORAGE_DRIVER=local`, `UPLOAD_PATH=./uploads` | lokální vývoj, CI testy |
| **s3** | `STORAGE_DRIVER=s3` + `S3_*` proměnné | Railway / produkce |

Bez S3 na Railway po restartu/redeploy mohou fyzické soubory zmizet, v DB zůstanou metadata bez souboru. Pro produkci použijte `STORAGE_DRIVER=s3`.
