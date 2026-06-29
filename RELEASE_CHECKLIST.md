# RELEASE_CHECKLIST.md – interní beta a ostré nasazení

Datum auditu: **2026-05-28** (finální MVP) · Aktualizace: **2026-06-27**

> **Stav 2026-06-27:** Produkce je **živá** na `https://firemni-production.up.railway.app` (HTTPS, PostgreSQL, R2/S3 storage). Většina „blokerů ostrého nasazení" z §2 níže je **vyřešena** — viz aktualizační poznámka v §2. Aktuální verze klienta: `1.0.8+9`.

Související: [BETA_TEST_PLAN.md](BETA_TEST_PLAN.md), [RUNNING.md](RUNNING.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md), [AUDIT_REPORT_NASAZENI.md](AUDIT_REPORT_NASAZENI.md), [docs/CI.md](docs/CI.md).

---

## 1. Shrnutí: co je hotové pro interní betu


| Oblast                                                                    | Stav             |
| ------------------------------------------------------------------------- | ---------------- |
| Backend API (auth, jobs, floors, seals, sync, reports, logs, admin trash) | hotové           |
| PostgreSQL + Prisma migrate/seed                                          | hotové           |
| Worker flow (stavba → patro → seznam → formulář/detail)                   | hotové           |
| Offline read (seznamy, patra, detail) + outbox + sync konflikty           | hotové           |
| Automatický sync retry (FE-06)                                            | hotové           |
| Management soupis CSV/PDF                                                 | hotové           |
| Admin koš + obnova ucpávek                                                |                  |
| Windows release build                                                     | hotové (PLAT-01) |
| Android release APK                                                       | hotové (PLAT-02) |
| GitHub Actions CI                                                         | hotové (DOC-01)  |



|        |
| ------ |
| hotové |


**Interní beta =** 1–2 pracovníci v terénu / kanceláři s **lokálním nebo LAN backendem**, Windows klient nebo Android APK, seed nebo reálná testovací data.

---

## 2. Co blokuje ostré (produkční) nasazení

> **Aktualizace 2026-06-27 — většina blokerů VYŘEŠENA:**
> - ✅ **Hostovaný backend** — běží na Railway (`https://firemni-production.up.railway.app`), klient (release APK) volá tuto HTTPS URL přes `--dart-define=API_BASE_URL`.
> - ✅ **HTTPS / cleartext** — produkce je HTTPS; Android `network_security_config` zakazuje cleartext globálně (povolen jen pro localhost/LAN dev domény).
> - ✅ **Android Play signing** — release APK je podepsané release keystorem (`key.properties` lokálně, secrets v CI).
> - ✅ **Storage** — `STORAGE_DRIVER=s3` (Cloudflare R2) vynucený a ověřený živě.
> - ◑ **Sync na pozadí (Doze)** — stále řešeno ručním syncem; WorkManager je budoucí task.
> - ☐ **Nepodepsaný Windows exe** — zbývá (SmartScreen „Spustit přesto"), nízká priorita.
> - ☐ **Koš jen pro ucpávky** — patra/stavby bez obnovy, zbývá.
> - ✅ **Provozní procesy** — živý restore test ze šifrované `.dump.age` zálohy proběhl 2026-06-28; nově se DB/object/restore běhy zapisují do `BackupRun`.
>
> Tabulka níže je původní (2026-05-28) a slouží jako kontext.

| Blokér                             | Důvod                                                                           | Co by bylo potřeba                                     |
| ---------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------ |
| **Lokální backend**                | Klient default `http://localhost:3000`; backend musí běžet na PC/serveru v síti | Hostovaný backend (VPS/cloud), DNS, monitoring         |
| **HTTP cleartext**                 | Android `network_security_config` + dev API bez TLS                             | HTTPS, certifikát, odstranit cleartext z release       |
| **Nepodepsaný Windows exe**        | SmartScreen, chybí MSI/instalátor                                               | Code signing + distribuční balíček                     |
| **Android bez Play signing**       | APK podepsané debug klíčem                                                      | Release keystore, Play App Signing nebo MDM distribuce |
| **Mobil na fyzickém zařízení**     | `localhost` na telefonu ≠ PC; nutná LAN IP nebo VPN                             | `--dart-define=API_BASE_URL=https://api.firma.cz`      |
| **Sync timer na pozadí (Android)** | Doze může zpomalit automatický sync                                             | Workmanager / foreground service (nový task)           |
| **Koš jen pro ucpávky**            | Patra/stavby bez list API                                                       | Backend + UI rozšíření                                 |
| **Produkční provoz**               | DB/object zálohy, restore testy a admin logy záloh jsou pokryté; průběžně hlídat alerty | DevOps + admin nástroje                                |


---

## 3. Test summary (ověření 2026-05-28)


| Oblast                   | Příkaz / artefakt                                    | Výsledek                                             |
| ------------------------ | ---------------------------------------------------- | ---------------------------------------------------- |
| **Backend**              | `cd backend && npm test`                             | **8 suites, 52/52 passed**                           |
| **Flutter analyze**      | `flutter analyze`                                    | **0 errors**, 2× info (`deprecated_member_use`)      |
| **Flutter unit/offline** | 6 souborů (offline, sync retry, widget, login smoke) | **18/18 passed**                                     |
| **Flutter runtime API**  | `runtime_verification_test.dart`                     | **12/12** (poslední audit; před betou znovu spustit) |
| **CI**                   | `.github/workflows/ci.yml`                           | backend + flutter-unit + flutter-runtime             |
| **Windows release**      | `build/windows/x64/runner/Release/ucpavky.exe`       | artefakt **existuje** (~34 MB složka)                |
| **Android APK**          | `build/app/outputs/flutter-apk/app-release.apk`      | artefakt **existuje** (~58 MB)                       |


```powershell
# Rychlé ověření před betou
cd backend && npm test
cd ..\frontend
flutter analyze
flutter test test/integration/runtime_verification_test.dart
flutter test test/seal_list_offline_test.dart test/floor_list_offline_test.dart test/sync_conflict_test.dart test/seal_detail_offline_test.dart test/sync_retry_test.dart test/widget_test.dart test/login_home_smoke_test.dart
```

Backend musí běžet na `:3000` pro runtime + login E2E smoke.

---

## 4. Instalace klientů (shrnutí)

Detailní postup: [RUNNING.md](RUNNING.md).

### Windows release

1. Sestavit: `cd frontend && flutter build windows --release`
2. Zkopírovat celou složku `frontend\build\windows\x64\runner\Release\` na cílový PC
3. Na stejném PC nebo v LAN spustit backend ([RUNNING.md](RUNNING.md) §3)
4. Spustit `ucpavky.exe` ze složky `Release\`

### Android APK

1. Sestavit: `cd frontend && flutter build apk --release`
2. Přenést `app-release.apk` na zařízení (USB, e-mail, MDM)
3. Povolit instalaci z neznámých zdrojů (jednorázově)
4. **Emulátor:** `adb reverse tcp:3000 tcp:3000` + backend na PC
5. **Telefon (Wi‑Fi):** backend dostupný na `http://<IP_PC>:3000`, build s
  `--dart-define=API_BASE_URL=http://<IP_PC>:3000`

---

## 5. Známá omezení (beta)


| Omezení                               | Dopad na betu                                                                                                                             |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Lokální / LAN backend                 | IT musí zajistit běžící server a firewall                                                                                                 |
| HTTP (cleartext)                      | Pouze v důvěryhodné síti; ne pro internet                                                                                                 |
| Nepodepsaný Windows exe               | SmartScreen – „Spustit přesto“                                                                                                            |
| Android debug signing                 | Pro pilotní distribuci vytvořit `frontend/android/key.properties` podle `key.properties.example`; bez něj je release APK jen debug-signed |
| Fyzický telefon                       | Nutná IP PC + stejná Wi‑Fi                                                                                                                |
| Automatický sync na Androidu v pozadí | Spolehnout se na ruční Sync                                                                                                               |
| Export CSV/PDF na Androidu            | Soubor v app documents; cesta ve SnackBar                                                                                                 |
| Web/Chrome klient                     | **Nepodporováno** (Drift/SQLite)                                                                                                          |


Více: [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

---

## 5b. Vydání nové verze Android klienta (update checker)

Po sestavení APK (`build-release.ps1` nebo `flutter build apk --release`):

1. Zvýšit `version` v `frontend/pubspec.yaml` (např. `1.1.0+2` — číslo za `+` je `APP_RELEASE_BUILD`).
2. Nahrát `app-release.apk` na **HTTPS** (GitHub Releases, R2 public URL, firemní CDN).
3. Na backendu nastavit env proměnné (viz `backend/.env.production.example`):
   - `APP_RELEASE_VERSION_NAME` — zobrazená verze
   - `APP_RELEASE_BUILD` — build číslo z pubspec
   - `APP_RELEASE_MIN_BUILD` — pod tímto buildem app vynutí aktualizaci
   - `APP_RELEASE_APK_URL` — HTTPS odkaz na APK
   - `APP_RELEASE_NOTES` — volitelný text změn
4. Restart / redeploy backendu.

Uživatelé se starším APK při příštím startu (online) uvidí dialog **Stáhnout aktualizaci** — bez ručního hledání souboru. Kontrola běží jen na **Android release** (ne v debug).

Ověření: `GET /api/app/release?platform=android` → JSON s `updateAvailable: true`.

---

## 5c. Kandidat release notes pro stabilizacni varku

> Aktualizace 2026-06-27: tato sekce je historická (psána u verze `1.0.2+3`).
> Aktuální `frontend/pubspec.yaml` je `1.0.8+9`; poslední dvě podepsané APK jsou
> v `releases/` (`1.0.7+8`, `1.0.8+9`). Pro postup vydání viz §8 a
> [memory release-flow]. Text níže popisuje princip kandidátních release notes.

Tato sekce je priprava vydani, ne bump verze ani build artefaktu.

Kandidatni `APP_RELEASE_NOTES`:

```text
- Zpresnene filtrovani aktivnich zakazek v dashboardu, upozornenich a sekci Vyzaduje akci.
- Lepsi ochrana viditelnosti jmen pracovniku a informaci o soupisu u ucpavek.
- Soupisy maji export centralizovany v seznamu a rozpracovane soupisy lze doplnovat o dalsi polozky.
- Prehlednejsi logy, notifikace a formular ucpavky.
```

Doporucene env po skutecnem buildu Android artefaktu:

```text
APP_RELEASE_VERSION_NAME=1.0.3
APP_RELEASE_BUILD=4
APP_RELEASE_MIN_BUILD=3
APP_RELEASE_APK_URL=https://<release-host>/ucpavky-1.0.3+4.apk
APP_RELEASE_NOTES=<text vyse>
```

Pro vynucenou aktualizaci nastavit `APP_RELEASE_MIN_BUILD=4`. Do te doby
ponechat `APP_RELEASE_MIN_BUILD=3`, aby build `1.0.2+3` nebyl blokovany.

---

## 5d. Produkcni R2/S3 storage gate

Pred ostrym redeployem backendu na Railway:

1. V Railway backend service nastav:
   - `STORAGE_DRIVER=s3`
   - `PUBLIC_UPLOADS=false`
   - `S3_BUCKET=<r2-bucket-name>`
   - `S3_ACCESS_KEY_ID=<r2-access-key-id>`
   - `S3_SECRET_ACCESS_KEY=<r2-secret-access-key>`
   - `S3_ENDPOINT=https://<cloudflare-account-id>.r2.cloudflarestorage.com`
   - `S3_REGION=auto`
   - `S3_FORCE_PATH_STYLE=true`
   - `S3_KEY_PREFIX=photos`
   - `VERIFY_STORAGE_ON_START=true`
2. Lokalne over R2 credentials:
   `cd backend && npm run storage:verify -- --env=../.env.local`
3. Vygeneruj kontrolni Railway env block:
   `cd backend && npm run storage:railway-env -- --env=../.env.local`
4. Po deployi over:
   - `GET /ready` -> `storage.driver = "s3"`, `storage.publicUploads = false`
   - `POST /api/admin/storage/verify` s admin bearer tokenem -> `ok = true`
   - upload/download jedne fotky pres `/api/seals/:id/photos` a `/api/photos/:id/file`
   - upload/download jednoho vykresu pres `/api/jobs/:jobId/floors/:floorId/drawing` a `/drawing/file`
5. Spust audit:
   `cd backend && npm run storage:audit -- --env=../.env.local`
6. Recovernute soubory backfillni:
   `cd backend && npm run storage:backfill-local -- --env=../.env.local --write`

Bez splneneho R2/S3 gate nebrat nove uploady jako bezpecne.

---

## 6. Checklist před spuštěním interní bety

### Infrastruktura

- PostgreSQL běží, DB `ucpavky` existuje
- `npx prisma migrate deploy` + `npx prisma db seed` (nebo produkční data)
- `backend/.env` správné `DATABASE_URL`, `JWT_SECRET`
- `npm run dev` nebo produkční `npm start` na portu **3000**
- `GET http://localhost:3000/health` → 200

### Klient

- Windows: celá složka `Release\` zkopírována, exe startuje
- Android: APK nainstalováno, API URL správně (reverse / LAN / dart-define)
- Seed účty předány testerům (`worker1`, `vedeni`, `admin` + PIN)

### Ověření

- `npm test` green
- `flutter test` runtime + unit green (viz §3)
- Ruční smoke: login → stavba `12345678` → patro → seznam (viz [BETA_TEST_PLAN.md](BETA_TEST_PLAN.md))

### Dokumentace pro testery

- Předán [BETA_TEST_PLAN.md](BETA_TEST_PLAN.md)
- Kontakt na správce backendu / síť

---

## 7. Po betě

- Sebrat feedback (šablona v BETA_TEST_PLAN.md §5)
- Zapsat nové bugy do issue listu / KNOWN_ISSUES
- Rozhodnout: další beta vs. krok k HTTPS/hostovanému API

---

## 8. Aktualizace klienta (in-app updater)

Klient se distribuuje mimo store (sideload APK / Windows instalátor). Novou verzi
oznámí **vestavěný updater**: při startu ([frontend/lib/main.dart](frontend/lib/main.dart)) a ručně přes nápovědu. Backend
hlásí poslední verzi přes `GET /api/app/release?platform=android|windows`
([backend/src/services/app-release.service.ts](backend/src/services/app-release.service.ts)) podle env proměnných.

### Vydání nové verze

1. **Bump verze:** ve [frontend/pubspec.yaml](frontend/pubspec.yaml) zvýšit `version: X.Y.Z+B`
   (`B` = build number — to porovnává updater).
2. **Tag:** `git tag vX.Y.Z && git push origin vX.Y.Z` → spustí
   [.github/workflows/release.yml](.github/workflows/release.yml): postaví podepsané APK + Windows instalátor
   (Inno Setup, [frontend/windows/installer.iss](frontend/windows/installer.iss)) a publikuje je jako assety GitHub Release.
3. **Railway env:** podle výpisu v summary workflow nastavit a restartovat:
   - Android: `APP_RELEASE_BUILD`, `APP_RELEASE_MIN_BUILD`, `APP_RELEASE_APK_URL`,
     `APP_RELEASE_VERSION_NAME`, `APP_RELEASE_NOTES`
   - Windows: `APP_RELEASE_WIN_BUILD`, `APP_RELEASE_WIN_MIN_BUILD`,
     `APP_RELEASE_WIN_URL`, `APP_RELEASE_WIN_VERSION_NAME`, `APP_RELEASE_WIN_NOTES`
4. **Ověření:** klient se starším buildem po startu nabídne dialog aktualizace.

### Vynucená aktualizace

Nastav `*_MIN_BUILD` = nový `*_BUILD`. Klient pod minimem dostane dialog, který
nejde zavřít — použij u breaking change sync/API, ať v terénu neběží nekompatibilní klient.

### GitHub Secrets pro podpis APK

`ANDROID_KEYSTORE_BASE64` (release `.jks` v base64), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. Keystore i `key.properties` jsou
gitignorované — v CI se rekonstruují ze secrets. Podpis musí být stálý, jinak
update nepřepíše dřívější instalaci.

---

## Shrnutí jednou větou

**Interní beta je připravená** s lokálním/LAN backendem a Windows/Android klientem; **ostré nasazení** vyžaduje HTTPS, hostovaný backend, podpis aplikací a provozní procesy mimo aktuální V1 scope.
