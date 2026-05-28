# RUNNING.md – Lokální spuštění Ucpávky V1

Tento návod předpokládá:
- **Node.js** 18+,
- **PostgreSQL nainstalovaný přímo ve Windows** (doporučená varianta),
- volitelně Flutter pro klienta.

> **Docker není potřeba.** `docker-compose.yml` zůstává v repozitáři jen jako volitelná alternativa.

**CI:** automatické testy na GitHubu při push/PR – viz [docs/CI.md](docs/CI.md).

**Interní beta:** [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) · [BETA_TEST_PLAN.md](BETA_TEST_PLAN.md)

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

## 5. Flutter (Windows)

Adresář: `c:\Users\vojte\Desktop\unifast\frontend`

API URL: `lib/core/config.dart` → `http://localhost:3000` (stejné v debug i release).

### 5.1 Debug (vývoj)

```powershell
flutter pub get
flutter run -d windows --debug
```

### 5.2 Release build (PLAT-01)

**Předpoklady:** `flutter doctor` bez chyb u **Visual Studio** (Desktop development with C++), Windows 10/11 SDK.

```powershell
cd c:\Users\vojte\Desktop\unifast\frontend
flutter pub get
flutter build windows --release
```

**Výstup (ověřeno 2026-05-27):**

```text
build\windows\x64\runner\Release\ucpavky.exe
```

Celá složka `Release\` (~34 MB) musí zůstat pohromadě – spouštějte `ucpavky.exe` **z této složky** (ne kopírovat jen exe).

| Soubor / složka | Účel |
|-----------------|------|
| `ucpavky.exe` | spustitelná aplikace |
| `flutter_windows.dll` | Flutter engine |
| `sqlite3.dll`, `sqlite3_flutter_libs_plugin.dll` | Drift / lokální SQLite |
| `flutter_secure_storage_windows_plugin.dll` | JWT v secure storage |
| `connectivity_plus_plugin.dll`, `file_selector_windows_plugin.dll` | síť, výběr souborů |
| `data\app.so` | AOT kód (release) |
| `data\icudtl.dat`, `data\flutter_assets\` | ICU + assety |

**Drift DB:** ukládá se do uživatelských dokumentů (`getApplicationDocumentsDirectory()`), typicky `%USERPROFILE%\Documents` – zápis bez admin práv.

### 5.3 Spuštění release + ověření flow

1. Backend musí běžet (sekce 3): `npm run dev` na `:3000`.
2. Spusťte release:

```powershell
cd c:\Users\vojte\Desktop\unifast\frontend\build\windows\x64\runner\Release
.\ucpavky.exe
```

3. Ruční checklist UI:
   - [ ] Login `worker1` / PIN `1234` → hlavní menu
   - [ ] **Stavba** → číslo `12345678` → patro → seznam ucpávek
   - [ ] (volitelně) Sync obrazovka – pending fronta

4. Automatická kontrola API (stejný backend jako release klient):

```powershell
cd c:\Users\vojte\Desktop\unifast\frontend
flutter test test/integration/runtime_verification_test.dart
```

**Poznámky:**

- Release exe není kódově podepsané – Windows SmartScreen může zobrazit varování (očekávané pro dev build).
- Pokud build selže `MSB1009`: chybí CMake / VS Build Tools – viz [KNOWN_ISSUES.md](KNOWN_ISSUES.md) §4.
- Dřívější problém s prázdným `windows/CMakeLists.txt` je vyřešen (`flutter create . --platforms=windows`).

---

## 6. Flutter (Android) – PLAT-02

Adresář: `c:\Users\vojte\Desktop\unifast\frontend`

### 6.1 Release APK

```powershell
cd c:\Users\vojte\Desktop\unifast\frontend
flutter pub get
flutter build apk --release
```

**Výstup (ověřeno 2026-05-28):** `build\app\outputs\flutter-apk\app-release.apk` (~58 MB).

**Oprávnění v release** (`android/app/src/main/AndroidManifest.xml`):

| Položka | Účel |
|---------|------|
| `INTERNET` | API volání (dříve chybělo v release – jen debug manifest) |
| `ACCESS_NETWORK_STATE` | `connectivity_plus` |
| `network_security_config` | HTTP k dev backendu (cleartext); produkce → HTTPS |

Fotky: `image_picker` používá systémový photo picker + `FileProvider` (bez legacy storage permission).

### 6.2 API URL na zařízení / emulátoru

Výchozí `http://localhost:3000` na **Androidu znamená samotné zařízení**, ne váš PC.

| Prostředí | URL backendu |
|-----------|----------------|
| **Emulátor** + `adb reverse` | `http://localhost:3000` (doporučeno) |
| **Emulátor** bez reverse | `http://10.0.2.2:3000` |
| **Fyzické zařízení** (stejná Wi‑Fi) | `http://<IP_PC>:3000` přes `--dart-define` |

```powershell
# Emulátor: přesměrování portu host → emulátor
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb reverse tcp:3000 tcp:3000

# Nebo build s explicitní URL (LAN / 10.0.2.2)
flutter build apk --release --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Backend na PC musí naslouchat na `0.0.0.0:3000` nebo být dostupný z LAN (firewall).

### 6.3 Instalace a debug run

```powershell
# Emulátor
flutter emulators --launch Medium_Phone_API_36.0
flutter install -d emulator-5554   # po build apk
# nebo
flutter run -d emulator-5554 --release
```

```powershell
& $adb install -r build\app\outputs\flutter-apk\app-release.apk
& $adb shell am start -n com.example.ucpavky/.MainActivity
```

### 6.4 Ověření runtime (checklist)

Před testem: backend + seed (sekce 3), `adb reverse` (emulátor).

- [ ] Aplikace naběhne bez crash (logcat bez `FATAL`)
- [ ] Login `worker1` / `1234`
- [ ] Worker: stavba `12345678` → patro → seznam
- [ ] Offline: vypnout Wi‑Fi → nová ucpávka → Sync pending
- [ ] Online: Sync → odeslání
- [ ] Management `vedeni`: CSV/PDF export (uloží do app documents / downloads – viz SnackBar cesta)
- [ ] Fotka u ucpávky (photo picker)

**Drift / storage:** SQLite v app-specific úložišti (`getApplicationDocumentsDirectory`), scoped storage bez `MANAGE_EXTERNAL_STORAGE`.

**Sync timer (FE-06):** `Timer.periodic` může být zpomalen v pozadí (battery optimization) – ruční sync na obrazovce Sync vždy funguje.

**Automatická kontrola API (host, stejný backend):**

```powershell
flutter test test/integration/runtime_verification_test.dart
```

---

## 7. Rychlý checklist backend runtime

- [ ] PostgreSQL služba běží (`localhost:5432`)
- [ ] existuje DB `ucpavky` a uživatel odpovídá `DATABASE_URL`
- [ ] `npx prisma migrate deploy` OK
- [ ] `npx prisma db seed` OK
- [ ] `npm run dev` běží
- [ ] `GET /health` → 200
- [ ] `POST /api/auth/login` → 200 + token
