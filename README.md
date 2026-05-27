# Ucpávky – evidencia požárních ucpávek (V1)

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

### 2. Backend

```bash
cd backend
cp ../.env.example .env
npm install
npx prisma migrate dev
npx prisma db seed
npm run dev
```

API běží na `http://localhost:3000`. Health: `GET /health`.

### 3. Frontend

```bash
cd frontend
flutter pub get
flutter run -d windows
# nebo: flutter run -d android
```

Nastavte API URL v `lib/core/config.dart` (výchozí `http://localhost:3000`).

## Seed účty (PIN: 1234)

| Jméno | Role |
|-------|------|
| admin | admin |
| vedeni | management |
| worker1 | worker |
| worker2 | worker |

## Testovací stavba

Číslo stavby: `12345678`

## Dokumentace

Viz složka [`docs/`](docs/).
