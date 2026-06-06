# RELEASE_CHECKLIST.md – interní beta a ostré nasazení

Datum auditu: **2026-05-28** (finální MVP)

Související: [BETA_TEST_PLAN.md](BETA_TEST_PLAN.md), [RUNNING.md](RUNNING.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md), [PROJECT_STATUS.md](PROJECT_STATUS.md), [docs/CI.md](docs/CI.md).

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


| Blokér                             | Důvod                                                                           | Co by bylo potřeba                                     |
| ---------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------ |
| **Lokální backend**                | Klient default `http://localhost:3000`; backend musí běžet na PC/serveru v síti | Hostovaný backend (VPS/cloud), DNS, monitoring         |
| **HTTP cleartext**                 | Android `network_security_config` + dev API bez TLS                             | HTTPS, certifikát, odstranit cleartext z release       |
| **Nepodepsaný Windows exe**        | SmartScreen, chybí MSI/instalátor                                               | Code signing + distribuční balíček                     |
| **Android bez Play signing**       | APK podepsané debug klíčem                                                      | Release keystore, Play App Signing nebo MDM distribuce |
| **Mobil na fyzickém zařízení**     | `localhost` na telefonu ≠ PC; nutná LAN IP nebo VPN                             | `--dart-define=API_BASE_URL=https://api.firma.cz`      |
| **Sync timer na pozadí (Android)** | Doze může zpomalit automatický sync                                             | Workmanager / foreground service (nový task)           |
| **Koš jen pro ucpávky**            | Patra/stavby bez list API                                                       | Backend + UI rozšíření                                 |
| **Chybí produkční provoz**         | Zálohy DB, logy, RBAC správa uživatelů v UI                                     | DevOps + admin nástroje                                |


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

## Shrnutí jednou větou

**Interní beta je připravená** s lokálním/LAN backendem a Windows/Android klientem; **ostré nasazení** vyžaduje HTTPS, hostovaný backend, podpis aplikací a provozní procesy mimo aktuální V1 scope.