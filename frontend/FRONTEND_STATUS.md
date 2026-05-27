# FRONTEND_STATUS.md – stav Flutter integrace (2026-05-27)

Ověřeno proti běžícímu backendu na `http://localhost:3000` (lokální PostgreSQL bez Dockeru).

Automatický test: `flutter test test/integration/runtime_verification_test.dart` → **10/10 passed**.

---

## Co funguje

| Oblast | Stav | Poznámka |
|--------|------|----------|
| `flutter analyze` | OK | 1× info (`prefer_const_constructors`) |
| Integrační testy API | OK | health, login, job by-number, floors, seals |
| Drift SQLite init | OK | tabulky + insert do `local_jobs`, `local_outbox` |
| Sync outbox init | OK | fronta `pending` mutací v SQLite |
| Login (API) | OK | `worker1/1234` → token + role `worker` |
| Reports CSV/PDF export (FE-04, FE-05) | OK | management: Dio bytes → Downloads; filtry stavba/status; `soupis_praci_YYYY-MM-DD.{csv,pdf}` |
| Zakázky / patra (API + offline) | OK | patra: API + Drift cache (FE-02); stavba přes číslo |
| Seznam ucpávek (API + offline) | OK | API first, cache do Drift; při výpadku čtení z `local_seals` (FE-01) |
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
| Offline-first read path | částečně – seznam ucpávek (FE-01) a patra (FE-02); detail ucpávky stále API |
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

- Offline read pro detail ucpávky (`SealDetailScreen`)
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
