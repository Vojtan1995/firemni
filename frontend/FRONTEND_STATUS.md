# FRONTEND_STATUS.md – stav Flutter integrace (2026-05-27)

Kontrolní audit po vlně report/export (FE-04, FE-05). Backend musí běžet na `http://localhost:3000`.

### Ověření testů (2026-05-27)

| Příkaz | Výsledek |
|--------|----------|
| `flutter test test/integration/runtime_verification_test.dart` | **10/10 passed** |
| `flutter test test/login_home_smoke_test.dart` | **2/2 passed** (FE-07 widget smoke) |
| `flutter test test/seal_list_offline_test.dart test/floor_list_offline_test.dart test/sync_conflict_test.dart` | **6/6 passed** |
| `flutter analyze` | **0 errors**, 2× info (`deprecated_member_use` v `reports_screen.dart`) |

---

## Co funguje

| Oblast | Stav | Poznámka |
|--------|------|----------|
| `flutter analyze` | OK | 2× info (`deprecated_member_use` v reports dropdownech) |
| Integrační testy API | OK | health, login, job, floors, seals, reports CSV/PDF, worker 403 |
| Offline/sync unit testy | OK | seal list, floor list, sync conflict (6 testů) |
| Widget smoke login → home (FE-07) | OK | UI bez sítě + E2E s backendem (`login_home_smoke_test.dart`) |
| Drift SQLite init | OK | tabulky + insert do `local_jobs`, `local_outbox` |
| Sync outbox init | OK | fronta `pending` mutací v SQLite |
| Login (API) | OK | `worker1/1234` → token + role `worker` |
| Reports CSV/PDF export (FE-04, FE-05) | OK | management: Dio bytes → Downloads; filtry stavba/status; `soupis_praci_YYYY-MM-DD.{csv,pdf}` |
| Zakázky / patra (API + offline) | OK | patra: API + Drift cache (FE-02); stavba přes číslo |
| Seznam ucpávek (API + offline) | OK | API first, cache do Drift; při výpadku čtení z `local_seals` (FE-01) |
| Detail ucpávky (API + offline) | OK | cache `jsonPayload` + fotky; Drift fallback + banner/chip (offline detail) |
| Spuštění Windows (debug) | OK | `flutter run -d windows --debug` |
| Worker flow (kód + API) | OK | login → číslo stavby → patro → seznam ucpávek (vše přes Dio) |

### Worker flow – napojení na reálné API

| Krok | Obrazovka | Endpoint / akce |
|------|-----------|-----------------|
| Login | `LoginScreen` | `POST /api/auth/login` + `SyncService.syncAll()` |
| Menu | `HomeScreen` | role-based menu |
| Číslo stavby | `JobNumberScreen` | `GET /api/jobs/by-number/:num` + cache do Drift |
| Patro | `FloorListScreen` | API + Drift cache; offline banner + chip |
| Seznam ucpávek | `SealListScreen` | API + Drift cache; offline banner + chip |
| Nová ucpávka | `SealFormScreen` | `POST /api/seals` + lokální Drift + outbox |

---

## Co je rozpracované

| Oblast | Stav |
|--------|------|
| Offline-first read path | hotové – seznamy (FE-01/02) i detail ucpávky (offline detail) |
| Sync po loginu | volá se `syncAll()`, ale plná konzistence UI ↔ server není všude dokončená |
| Konflikty sync | SyncScreen zobrazuje konflikty, indikátor v seznamu ucpávek (FE-03) |
| Fotky | upload při online save, retry fronta v `SyncService` |
| Windows release build | `flutter build windows` (Release) může selhat na INSTALL kroku |

---

## Co je mock / fake

**Nic v produkčním kódu `lib/`** – nebyly nalezeny mock/fake datové zdroje.

Testovací pomůcky:
- `AppDatabase.forTesting()` – in-memory Drift pouze pro integrační testy
- seed hint na login obrazovce (`worker1 / 1234`)

---

## Co je napojené na reálné API

Všechny hlavní obrazovky používají `dioProvider` → `http://localhost:3000`:

- Auth: `/api/auth/login`, `/api/auth/logout`, `/api/auth/me`
- Jobs: `/api/jobs/by-number/:num`, `/api/jobs/:jobId/floors`
- Seals: `/api/seals/floors/:floorId/seals`, `/api/seals/:id`, `POST /api/seals`
- Photos: `POST /api/seals/:id/photos`
- Sync: `/api/sync/push`, `/api/sync/pull`
- Management: `/api/jobs`, `/api/reports/work-summary`, `/api/reports/export/csv`, `/api/reports/export/pdf`, `/api/logs/activity`

---

## Co ještě není implementované / neověřené v UI

- Automatické řešení konfliktů (záměrně mimo scope – pouze zobrazení)
- Kompletní management workflow (kontrola statusů v terénním UX)
- Push notifikace, diskuze, ceník (mimo V1 scope)
- Android build v tomto kole neověřován (dříve APK build prošel)
- Web/Chrome target – **nefunguje** kvůli `drift`/SQLite FFI (očekávané)

---

## Jak spustit ověření

```powershell
# Backend musí běžet na :3000
cd c:\Users\vojte\Desktop\unifast\frontend
flutter pub get
flutter test test/integration/runtime_verification_test.dart
flutter test test/login_home_smoke_test.dart
flutter test test/seal_detail_offline_test.dart
flutter test test/seal_list_offline_test.dart
flutter test test/floor_list_offline_test.dart
flutter test test/sync_conflict_test.dart
flutter run -d windows --debug
```

---

## Provedené opravy v tomto kole

### 1) `windows/CMakeLists.txt` byl placeholder
- **Problém:** soubor obsahoval jen komentář → `flutter run/build` selhával (`MSB1009`).
- **Oprava:** smazán placeholder + `flutter create . --platforms=windows` vygeneroval validní CMake.

### 2) Integrační testy padaly na falešné HTTP 400
- **Problém:** `flutter test` s default bindingem blokuje reálnou síť.
- **Oprava:** `IntegrationTestWidgetsFlutterBinding` + `dart:io` HttpClient v testu.

### 3) FE-04 – CSV export v ReportsScreen
- **Problém:** tlačítko Export CSV jen zobrazovalo URL bez auth.
- **Oprava:** `GET /api/reports/export/csv` přes Dio (bytes), uložení `soupis_praci_YYYY-MM-DD.csv` do Downloads, filtry stavba/status, SnackBar úspěch/chyba, router redirect worker → `/`.

### 4) FE-05 – PDF export v ReportsScreen
- **Oprava:** `GET /api/reports/export/pdf`, stejné filtry a uložení `soupis_praci_YYYY-MM-DD.pdf`; runtime test ověřuje hlavičku `%PDF` a worker `403`.

### 5) Login obrazovka overflow na Windows
- **Problém:** `Column` + `Spacer` přetékala layout (`RenderFlex overflow`).
- **Oprava:** `SingleChildScrollView`, odstraněn `Spacer`, upřesněný text tlačítka.

---

### 6) FE-07 – widget smoke login → home
- **Soubor:** `test/login_home_smoke_test.dart`
- **Strategie:** izolovaný `LoginScreen` bez sítě; E2E přes router + reálné `POST /api/auth/login` (backend `:3000`), sync v testu no-op override.
- **Keys:** `login_username`, `login_pin`, `login_submit` – stabilní `find.byKey` v pump testu.

### 7) Offline detail ucpávky – `SealDetailScreen`
- **Oprava:** API first + `cacheSealDetailFromApi` (`jsonPayload`, entries, materiály, metadata fotek); offline čtení z Drift, chip/banner „Offline data“, hláška bez cache.
- **Test:** `test/seal_detail_offline_test.dart` (3 testy).

## Další krok

1. **Admin restore UI** – existující restore endpoint.  
2. **FE-06** – sync retry timer.  
3. **DOC-01** – CI pipeline.
