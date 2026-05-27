# FRONTEND_STATUS.md – stav Flutter integrace (2026-05-27)

Ověřeno proti běžícímu backendu na `http://localhost:3000` (lokální PostgreSQL bez Dockeru).

Automatický test: `flutter test test/integration/runtime_verification_test.dart` → **6/6 passed**.

---

## Co funguje

| Oblast | Stav | Poznámka |
|--------|------|----------|
| `flutter analyze` | OK | 1× info (`prefer_const_constructors`) |
| Integrační testy API | OK | health, login, job by-number, floors, seals |
| Drift SQLite init | OK | tabulky + insert do `local_jobs`, `local_outbox` |
| Sync outbox init | OK | fronta `pending` mutací v SQLite |
| Login (API) | OK | `worker1/1234` → token + role `worker` |
| Zakázky / patra (API) | OK | `12345678` + `/api/jobs/:id/floors` |
| Seznam ucpávek (API) | OK | `/api/seals/floors/:floorId/seals` |
| Spuštění Windows (debug) | OK | `flutter run -d windows --debug` |
| Worker flow (kód + API) | OK | login → číslo stavby → patro → seznam ucpávek (vše přes Dio) |

### Worker flow – napojení na reálné API

| Krok | Obrazovka | Endpoint / akce |
|------|-----------|-----------------|
| Login | `LoginScreen` | `POST /api/auth/login` + `SyncService.syncAll()` |
| Menu | `HomeScreen` | role-based menu |
| Číslo stavby | `JobNumberScreen` | `GET /api/jobs/by-number/:num` + cache do Drift |
| Patro | `FloorListScreen` | `GET /api/jobs/:jobId/floors` |
| Seznam ucpávek | `SealListScreen` | `GET /api/seals/floors/:floorId/seals` |
| Nová ucpávka | `SealFormScreen` | `POST /api/seals` + lokální Drift + outbox |

---

## Co je rozpracované

| Oblast | Stav |
|--------|------|
| Offline-first read path | částečně – zápis do Drift při otevření stavby, ale seznamy primárně čtou z API |
| Sync po loginu | volá se `syncAll()`, ale plná konzistence UI ↔ server není všude dokončená |
| Konflikty sync | backend + outbox existují, UI pro řešení konfliktů je minimální |
| Fotky | upload při online save, retry fronta v `SyncService` |
| Management export CSV | tlačítko ukazuje URL, bez plného download flow v UI |
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
- Management: `/api/jobs`, `/api/reports/work-summary`, `/api/logs/activity`

---

## Co ještě není implementované / neověřené v UI

- Plný offline režim pro všechny seznamy (read z Drift místo API)
- UI pro ruční řešení sync konfliktů
- Kompletní management workflow (kontrola statusů v terénním UX)
- PDF export z mobilního UI
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

### 3) Login obrazovka overflow na Windows
- **Problém:** `Column` + `Spacer` přetékala layout (`RenderFlex overflow`).
- **Oprava:** `SingleChildScrollView`, odstraněn `Spacer`, upřesněný text tlačítka.
