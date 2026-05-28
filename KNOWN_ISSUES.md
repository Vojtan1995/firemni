# KNOWN_ISSUES.md – známé problémy a omezení

## 1. PostgreSQL není spuštěný → Prisma chyby (P1001)

- **Projev:** `npx prisma migrate deploy`, `npx prisma db seed`, login na `/api/auth/login` končí:

  ```text
  P1001: Can't reach database server at `localhost:5432`
  ```

- **Příčina:** PostgreSQL služba ve Windows neběží, nebo `DATABASE_URL` neodpovídá reálným přihlašovacím údajům.
- **Oprava:** postup v [`RUNNING.md`](RUNNING.md) sekce 1 (lokální PostgreSQL bez Dockeru):
  1. nainstalovat/spustit PostgreSQL,
  2. vytvořit DB `ucpavky` (`docs/setup-local-postgres.sql`),
  3. zkontrolovat `backend/.env`,
  4. `npx prisma migrate deploy` + `npx prisma db seed`.

## 2. Docker je volitelný (aktuálně se nepoužívá)

- **Stav:** Docker Desktop na tomto PC stabilně nenabíhá (engine API vrací HTTP 500).
- **Dopad:** `docker compose up` není podporovaná cesta pro lokální vývoj na tomto stroji.
- **Náhrada:** lokální PostgreSQL instalace ve Windows (primární postup v `RUNNING.md`).
- **Poznámka:** `docker-compose.yml` zůstává v repu pro jiné stroje/CI, ale není povinný.

## 3. Login vrací 500, když DB není připravená

- **Projev:** `POST /api/auth/login` → `{"error":"Interní chyba serveru","code":"INTERNAL_ERROR"}` a v logu backendu Prisma P1001.
- **Příčina:** backend běží, ale databáze není dostupná nebo není seednutá.
- **Oprava:** dokončit kroky z bodu 1; `/health` může fungovat i bez DB, login vyžaduje funkční PostgreSQL.

## 4. Flutter build Windows – toolchain

- **Projev:** `flutter build windows` skončí `MSBUILD : error MSB1009` (projektový soubor neexistuje).
- **Příčina:** chybí Visual Studio Build Tools / CMake / Windows SDK, nebo poškozený `frontend/windows/`.
- **Oprava:** doinstalovat workload **Desktop development with C++**, `flutter doctor`, případně znovu `flutter create . --platforms=windows` ve složce `frontend/`.

### 4.1 Windows Release – stav (PLAT-01, 2026-05-27)

- **Ověřeno:** `flutter build windows --release` → `build\windows\x64\runner\Release\ucpavky.exe` (Flutter 3.44, VS 2022).
- **CMake INSTALL:** součást standardního release buildu (kopíruje DLL, `data\flutter_assets`, `app.so`) – není samostatný krok.
- **Spuštění:** kopírovat / distribuovat celou složku `Release\`, ne jen exe.
- **SmartScreen:** nepodepsaný exe – uživatel může potvrdit „Spustit přesto“.
- **API:** release používá stejné `http://localhost:3000` – bez běžícího backendu login selže (ne chyba buildu).

## 5. Flutter build APK – varování pluginů

- **Projev:** varování Kotlin Gradle Plugin u `image_picker_android`, `flutter_image_compress_common`.
- **Dopad:** build APK proběhne (ověřeno PLAT-02); budoucí Flutter verze mohou vyžadovat upgrade pluginů.

## 6. Android runtime (PLAT-02)

### 6.1 Release APK bez INTERNET (opraveno)

- **Projev:** release APK nevolá API; login „visí“ / síťová chyba.
- **Příčina:** `INTERNET` byl jen v `android/app/src/debug/AndroidManifest.xml`, release merge ho neměl.
- **Oprava:** `uses-permission INTERNET` v `android/app/src/main/AndroidManifest.xml` (commit PLAT-02).

### 6.2 Cleartext HTTP

- **Projev:** `Cleartext HTTP traffic to … not permitted`.
- **Příčina:** Android 9+ blokuje HTTP; dev backend běží na `http://`.
- **Oprava:** `res/xml/network_security_config.xml` + `android:networkSecurityConfig` (dev/test). **Produkce:** HTTPS + odstranit cleartext.

### 6.3 `localhost` na zařízení

- **Projev:** aplikace na telefonu/emulátoru se nemůže připojit k `http://localhost:3000` na PC.
- **Příčina:** `localhost` = loopback zařízení.
- **Workaround:**
  - emulátor: `adb reverse tcp:3000 tcp:3000` a ponechat výchozí URL;
  - emulátor bez reverse: `--dart-define=API_BASE_URL=http://10.0.2.2:3000`;
  - telefon: IP PC na LAN + `--dart-define=API_BASE_URL=http://192.168.x.x:3000`.

### 6.4 Sync timer na pozadí

- **Projev:** automatický sync (FE-06, každých 15 s) po zhasnutí obrazovky nebo v pozadí neběží spolehlivě.
- **Příčina:** Android battery / Doze omezuje timery.
- **Workaround:** ruční **Synchronizovat** na `SyncScreen`; po návratu do popředí timer pokračuje.

### 6.5 Export CSV/PDF na Androidu

- **Chování:** `getDownloadsDirectory()` nemusí být dostupné → fallback `getApplicationDocumentsDirectory()`.
- **Dopad:** soubor je v app-specific složce; cesta se zobrazí ve SnackBar (scoped storage, bez legacy permission).
