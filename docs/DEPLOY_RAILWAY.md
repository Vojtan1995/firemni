# DEPLOY_RAILWAY.md

Minimální postup pro nasazení backendu na Railway pro demo/beta provoz.

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
- `CORS_ORIGIN=*` pro uzavřenou demo betu (pro ostrý provoz whitelist)
- `UPLOAD_PATH=./uploads`

Poznámka:
- `PORT` dodává Railway automaticky.

## 4) Build/start/migrate/seed

- Build: `npm ci && npm run build`
- Start: `npm run start`
- Migrace: `npx prisma migrate deploy` (nebo `npm run prisma:migrate:deploy`)
- Seed (volitelně demo data): `npx prisma db seed` (nebo `npm run prisma:seed`)

## 5) Ruční nasazení krok za krokem
1. Připojte repozitář do Railway.
2. Vytvořte `backend` service se rootem `backend`.
3. Přidejte PostgreSQL service.
4. Nastavte variables dle sekce 3.
5. Spusťte deploy.
6. Po prvním deployi spusťte migrace:
   - `npx prisma migrate deploy`
7. Volitelně spusťte seed:
   - `npx prisma db seed`
8. Ověřte:
   - `GET https://<backend-domain>/health`
   - `POST https://<backend-domain>/api/auth/login`

## 6) Android APK na veřejnou URL
Po nasazení backendu sestavte APK:

`flutter build apk --release --dart-define=API_BASE_URL=https://<backend-domain>`

## 7) Důležité omezení uploadů (demo-only)
Aktuální uploady (`UPLOAD_PATH=./uploads`) používají lokální filesystem instance.
Na Railway to není perzistentní úložiště pro ostrý provoz.

To znamená:
- po restartu/redeploy mohou soubory zmizet,
- v DB zůstanou metadata bez fyzických souborů.

Tato varianta je pouze pro demo/beta.
