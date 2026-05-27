# RUNNING.md – Lokální spuštění Ucpávky V1

Tento návod předpokládá, že máte:
- nainstalovaný **Node.js** (18+),
- nainstalovaný **Flutter** (ověřeno `flutter --version`),
- nainstalovaný **PostgreSQL** (lokálně nebo přes Docker Desktop).

## 1. Databáze PostgreSQL

### 1.1 Varianta A – ruční PostgreSQL (bez Dockeru)

1. Spusťte PostgreSQL lokálně na `localhost:5432`.
2. Vytvořte databázi:

```sql
CREATE DATABASE ucpavky;
```

3. Ujistěte se, že přihlašovací údaje odpovídají `backend/.env`:

```bash
DATABASE_URL=postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky
```

Buď vytvořte uživatele `ucpavky` s heslem `ucpavky_dev`, nebo upravte `DATABASE_URL` na vaše vlastní jméno a heslo.

### 1.2 Varianta B – Docker Compose (pokud máte Docker)

> Na tomto stroji zatím Docker není v PATH (`docker` příkaz selhal). Pokud Docker používáte, stačí:

```bash
cd c:\Users\vojte\Desktop\unifast
docker compose up -d
```

To spustí PostgreSQL s uživatelem `ucpavky/ucpavky_dev` a DB `ucpavky` podle `docker-compose.yml`.

## 2. Backend (Node.js / Express)

Adresář: `c:\Users\vojte\Desktop\unifast\backend`

### 2.1 Instalace závislostí

```bash
cd c:\Users\vojte\Desktop\unifast\backend
npm install
```

### 2.2 Migrace databáze (Prisma)

> Vyžaduje běžící PostgreSQL dle kroku 1.

```bash
cd c:\Users\vojte\Desktop\unifast\backend
npx prisma migrate deploy
```

### 2.3 Seed databáze

> Vyžaduje úspěšné migrace.

```bash
cd c:\Users\vojte\Desktop\unifast\backend
npx prisma db seed
```

Seed vytvoří:
- uživatele: `admin`, `vedeni`, `worker1`, `worker2` (PIN `1234`),
- testovací stavbu `12345678` se dvěma patry.

### 2.4 Spuštění backendu

```bash
cd c:\Users\vojte\Desktop\unifast\backend
npm run dev
```

Server běží na:

```text
http://localhost:3000
```

Zdravotní endpoint:

```bash
curl http://localhost:3000/health
```

Očekávaná odpověď: `{"status":"ok", ... }`.

### 2.5 Rychlý test loginu

```bash
curl -X POST http://localhost:3000/api/auth/login ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"worker1\",\"pin\":\"1234\"}"
```

Očekávaná odpověď: JSON s `token` a `user` (role `worker`).

## 3. Flutter aplikace (Android + Windows)

Adresář: `c:\Users\vojte\Desktop\unifast\frontend`

### 3.1 Instalace závislostí

```bash
cd c:\Users\vojte\Desktop\unifast\frontend
flutter pub get
```

### 3.2 Běh na Windows

```bash
cd c:\Users\vojte\Desktop\unifast\frontend
flutter run -d windows
```

Aplikace se připojuje na backend:

```dart
// lib/core/config.dart
static const String apiBaseUrl = 'http://localhost:3000';
```

### 3.3 Build pro Windows

> Vyžaduje nainstalovaný Windows desktop toolchain (CMake, MSVC / Visual Studio Build Tools).

```bash
cd c:\Users\vojte\Desktop\unifast\frontend
flutter build windows
```

Výstup: `build\windows\x64\runner\Release\`.

### 3.4 Build pro Android (APK)

> Vyžaduje nainstalovaný Android SDK, platform tools a alespoň jeden Android target.

```bash
cd c:\Users\vojte\Desktop\unifast\frontend
flutter build apk
```

Výstup: `build\app\outputs\flutter-apk\app-release.apk`.

## 4. Login flow v UI

Předpoklady:
- běží backend (`npm run dev`),
- databáze je migrovaná a seednutá.

Postup:
1. Spusťte Flutter app na Windows: `flutter run -d windows`.
2. Na přihlašovací obrazovce zadejte:
   - uživatel: `worker1`
   - PIN: `1234`
3. Po přihlášení se zobrazí hlavní menu (Stavba, Synchronizace, Profil, Nápověda).

Pro roli management:
- uživatel: `vedeni`
- PIN: `1234`
- v menu přibudou položky Správa/Export/Logy.

## 5. Testovací skripty / kontroly

### 5.1 Backend – testy + TypeScript

```bash
cd c:\Users\vojte\Desktop\unifast\backend
npm test
npx tsc --noEmit
```

### 5.2 Flutter – statická analýza

```bash
cd c:\Users\vojte\Desktop\unifast\frontend
flutter analyze
```

