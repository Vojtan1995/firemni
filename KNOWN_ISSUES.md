# KNOWN_ISSUES.md – známé problémy a omezení

Tento soubor popisuje aktuální známé problémy při lokálním běhu projektu.

## 1. PostgreSQL není spuštěný → Prisma chyby (P1001)

- **Projev:** příkazy
  - `npx prisma migrate deploy`
  - `npx prisma db seed`
  - login request na `/api/auth/login`
  končí chybou:

  ```text
  P1001: Can't reach database server at `localhost:5432`
  ```

- **Příčina:** na tomto stroji neběží PostgreSQL na `localhost:5432` podle `backend/.env`.
- **Oprava:** spustit PostgreSQL podle `RUNNING.md` (ručně nebo přes Docker Compose). Až DB běží:
  - znovu spustit `npx prisma migrate deploy`,
  - znovu spustit `npx prisma db seed`,
  - poté login funguje (API i Flutter UI).

## 2. Docker není nainstalovaný / není v PATH

- **Projev:** příkaz

  ```bash
  cd c:\Users\vojte\Desktop\unifast
  docker compose ps
  ```

  končí na Windows chybou:

  ```text
  'docker' is not recognized as the name of a cmdlet, function, script file, or operable program.
  ```

- **Příčina:** Docker Desktop / CLI není nainstalován nebo není v PATH.
- **Oprava:** nainstalovat Docker Desktop a ověřit `docker --version`. Poté lze používat `docker compose up -d` dle `RUNNING.md`. Do té doby je nutné PostgreSQL spustit jiným způsobem (lokální instalace).

## 3. Flutter build Windows – závislost na Windows toolchainu

- **Projev:** příkaz

  ```bash
  cd c:\Users\vojte\Desktop\unifast\frontend
  flutter build windows
  ```

  skončil chybou MSBuild:

  ```text
  MSBUILD : error MSB1009: Soubor projektu neexistuje.
  Build process failed.
  ```

- **Příčina:** chybějící / nedokonfigurovaný Windows desktop toolchain (Visual Studio Build Tools, CMake, Windows SDK). Flutter CLI vytvořil skeleton `windows/`, ale MSBuild nenašel požadovaný projektový soubor/SDK.
- **Aktuální stav:** projektovou strukturu jsme neměnili; problém je čistě v lokální konfiguraci nástrojů.
- **Oprava:** doinstalovat:
  - Visual Studio / Build Tools s workloadem „Desktop development with C++“,
  - CMake a Windows 10/11 SDK.

  Poté znovu spustit:

  ```bash
  flutter config --enable-windows-desktop
  flutter doctor
  flutter build windows
  ```

## 4. Flutter build APK – varování, ale build OK

- **Projev:** `flutter build apk` proběhl úspěšně (`app-release.apk` vytvořen), ale s varováním:

  - pluginy `flutter_image_compress_common`, `image_picker_android` používají Kotlin Gradle Plugin,
  - varování o `source value 8` a `target value 8` v Javě.

- **Příčina:** standardní deprecation varování v aktuálním Flutter toolchainu a pluginech.
- **Aktuální dopad:** build úspěšný, APK se vytvoří. Není to blokér pro V1.
- **Doporučení do budoucna:** při aktualizaci Flutteru a pluginů sledovat release notes pro podporu „Built-in Kotlin“ a novější JDK level.

## 5. Login flow padá, pokud neběží databáze

- **Projev:** POST na `/api/auth/login` vrací:

  ```json
  {"error":"Interní chyba serveru","code":"INTERNAL_ERROR"}
  ```

  a v logu backendu je `PrismaClientInitializationError` s P1001 (`Can't reach database server`).

- **Příčina:** backend správně používá Prisma a očekává běžící PostgreSQL; pokud DB nesedí s `DATABASE_URL` nebo server neběží, login logicky selže.
- **Oprava:** stejná jako v bodě 1 – spustit DB a migrace/seed dle `RUNNING.md`. Kód není třeba refaktorovat, jde o chybějící infrastrukturu.

