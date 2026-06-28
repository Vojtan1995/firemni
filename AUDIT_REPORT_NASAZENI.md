# Audit připravenosti k reálnému nasazení — Ucpávky (unifast)

Datum auditu: 2026-06-13 · Rozsah: backend (Express/TS/Prisma), Flutter frontend, konfigurace, CI/CD, závislosti, role.

> **STAV K 2026-06-27 — všechny 3 KRITICKÉ nálezy a klíčové vážné body jsou OPRAVENÉ a produkce je živá.**
> Backend běží na `https://firemni-production.up.railway.app` (`/ready` → `database: ok`, `storage.driver: s3`, `publicUploads: false`). Multer je na 2.x, `trust proxy` nastaven, PIN má min. 6 znaků + per-účtový lockout + `mustChangePin`, CORS prod šablona bez wildcardu, git repozitář zdravý, R2/S3 storage vynucený. Doplněn také per-uživatelský rate limiting na zprávy, sync push a CSV/PDF exporty. Detaily níže (sekce 2 a 3 jsou označeny ✅/zbývá).
>
> Aktuální verdikt: **způsobilé pro interní produkční nasazení (desítky uživatelů firmy).** Pro vystavení na veřejný internet zvážit ještě silnější autentizaci než PIN.

Dodatek 2026-06-23: storage riziko `STORAGE_DRIVER=local` na Railway je v kodu osetrene fail-fast validaci. Produkce vyzaduje `STORAGE_DRIVER=s3`, `PUBLIC_UPLOADS=false`, `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`; lokalni storage v produkci projde jen s nouzovym `ALLOW_LOCAL_STORAGE_IN_PRODUCTION=true`. Operacni postup je v `docs/R2_STORAGE_RUNBOOK.md`.

---

## Verdikt (původní, 2026-06-13)

**Připraveno pro řízený interní pilot (beta) — NE pro otevřené produkční nasazení bez oprav níže.**

Aplikace je na poměry interního firemního nástroje nadprůměrně zabezpečená a otestovaná. Bezpečnostní základ (session-based JWT, RBAC matice, validace, fail-fast konfigurace) je solidní. Brání jí ale 3 kritické a několik vážných nálezů — hlavně zranitelná verze multeru, chybějící `trust proxy` (rozbíjí rate limiting za reverzní proxy), a slabý PIN model bez per-účtového lockoutu.

> Poznámka 2026-06-27: tyto 3 kritické nálezy jsou nyní vyřešené — viz označení ✅ v sekci 2.

---

## 1. Co je uděláno dobře (důvody pro „skoro ano")

| Oblast | Detail | Kde |
|---|---|---|
| Autentizace | JWT + serverová session tabulka s hashovaným tokenem → tokeny lze revokovat; kontrola `isActive` při každém requestu; invalidace všech sessions při změně PIN/deaktivaci | `backend/src/middleware/auth.middleware.ts`, `backend/src/services/auth.service.ts`, `backend/src/services/user.service.ts:118-122` |
| RBAC | Centrální permission matice (31 oprávnění × 4 role), konzistentně používaná přes `requirePermission` | `backend/src/lib/permissions.ts` |
| Hierarchie rolí | `vedeni` nemůže vytvářet/upravovat admin účty ani přiřadit roli admin; admin účty se vedení nezobrazují v seznamu; nelze deaktivovat vlastní účet | `backend/src/services/user.service.ts:35-47,95` |
| Scoping workera | Worker vidí jen zakázky, kde je participant; mazané/uzavřené joby blokují zápis (`assertJobWritable`); platí i v sync endpointech | `backend/src/services/authorization.service.ts`, `backend/src/routes/sync.routes.ts` |
| Fail-fast produkce | `validateConfig()` shodí start, pokud je v produkci defaultní `JWT_SECRET`, wildcard CORS bez explicitního souhlasu, nenastavené `PUBLIC_UPLOADS`, chybějící S3 proměnné | `backend/src/config.ts` |
| Upload fotek | Whitelist MIME+přípona, limit 15 MB (výkresy 25 MB), **re-enkódování přes sharp do WebP** (eliminuje polyglot/payload soubory), ochrana proti path traversal (`sanitizeObjectKey`) | `backend/src/routes/photos.routes.ts`, `backend/src/services/storage.service.ts:13-42` |
| Autorizace fotek | `GET /photos/:id/file` ověřuje přístup k ucpávce → fotky nejsou veřejné (pokud `PUBLIC_UPLOADS=false`) | `backend/src/routes/photos.routes.ts:122-142` |
| Error handling | Centrální middleware, 500 neprozrazuje stack, Zod chyby → 400 s detaily; logování pino + ErrorLog + volitelný Sentry | `backend/src/middleware/error.middleware.ts`, `backend/src/index.ts` |
| Seed | V produkci vyžaduje `SEED_DEMO_PIN`, jinak spadne | `backend/prisma/seed.ts:7-13` |
| Testy + CI | 40 testovacích souborů vč. integračních (RBAC, autorizace, fotky, pricing, sync) běžících proti reálnému PostgreSQL v GitHub Actions; Flutter analyze + unit + runtime testy | `backend/__tests__/`, `.github/workflows/ci.yml` |
| Zálohy | Denní `pg_dump` → R2/S3 přes GitHub Actions s 30denní retencí | `.github/workflows/backup.yml` |
| Frontend | Token ve `flutter_secure_storage`; release build **vynucuje** `--dart-define=API_BASE_URL` (nespustí se proti localhostu omylem) | `frontend/lib/core/config.dart`, `frontend/lib/features/auth/auth_provider.dart` |
| Dokumentace | Nadstandardní: RUNNING, KNOWN_ISSUES, RELEASE_CHECKLIST, DEPLOY_RAILWAY, docs/* | kořen repa |

---

## 2. KRITICKÉ — blokuje produkci → ✅ VŠE VYŘEŠENO (2026-06-27)

> Všechny tři kritické nálezy níže jsou opravené v aktuální `main`. Původní text je ponechán jako kontext, stav je doplněn na začátku každého bodu.

### 2.1 Zranitelná závislost: multer 1.4.5-lts.2
**✅ VYŘEŠENO:** `backend/package.json` nyní `"multer": "^2.2.0"` (`@types/multer` `^2.0.0`), nainstalováno 2.2.0.
- Nainstalovaná řada multer 1.x má známé DoS zranitelnosti (CVE-2025-47935 — memory leak při chybě streamu, CVE-2025-47944 — crash na malformovaný multipart, CVE-2025-7338); opraveno až v multeru 2.x.
- Používá se na obou upload endpointech (fotky, výkresy podlaží). Neautentizovaný útočník se k nim nedostane (auth middleware je před nimi), ale kterýkoli přihlášený worker může server shodit.
- **Doporučení:** upgrade na `multer@^2`. (`backend/package.json` — `"multer": "^1.4.5-lts.1"`)
- Pozn.: `npm audit` se v sandboxu nepodařilo spustit (blokovaná síť) — před nasazením spustit lokálně pro úplný obraz.

### 2.2 Chybí `app.set('trust proxy', …)`
**✅ VYŘEŠENO:** `backend/src/app.ts:36` nastavuje `app.set('trust proxy', 1)`.
- V `backend/src/app.ts` není trust proxy nastaven, přitom cílový deploy je Railway (za reverzní proxy).
- Důsledky: `req.ip` = IP proxy pro všechny klienty → **login rate limiter (30 pokusů/15 min/IP) se sečte přes všechny uživatele firmy** — buď zamkne legitimní uživatele, nebo (podle proxy) naopak útočník rotuje X-Forwarded-For. Také `LoginLog.ipAddress` bude k ničemu.
- **Doporučení:** `app.set('trust proxy', 1)` + ověřit chování express-rate-limit za Railway.

### 2.3 Slabý PIN model bez per-účtového lockoutu
**✅ VYŘEŠENO:** PIN min. 6 znaků (`auth.routes.ts` — `z.string().min(6).max(8)`), per-účtový lockout (10 neúspěšných pokusů / 15 min přes `LoginLog`, `auth.service.ts:checkAccountLockout`), `mustChangePin: true` v seedu a `SEED_DEMO_PIN` povinný v produkci. Zbývá zvážit: pro admin účty silnější heslo místo PINu.
- PIN 4–8 znaků (`backend/src/routes/auth.routes.ts:11`, schéma nevynucuje ani číslice, ale 4 znaky jsou málo), bcrypt cost 10.
- Rate limit je jen per-IP (viz 2.2) — **neexistuje lockout per účet**. 4místný PIN = 10 000 kombinací; při distribuovaném útoku reálně prolomitelné. Při úniku DB je offline crack 4–8místných PINů triviální i s bcryptem.
- Seed (`backend/prisma/seed.ts`) navíc dává **všem 5 účtům včetně admina stejný PIN** a `mustChangePin` nenastavuje (default `false` — `backend/prisma/schema.prisma:44`) → seednutý admin si PIN nikdy nemusí změnit.
- **Doporučení:** min. 6 znaků, lockout/zpomalení per účet (využít existující `LoginLog`), `mustChangePin: true` v seedu, pro admin účty delší heslo místo PINu.

---

## 3. VÁŽNÉ — opravit před/při nasazení

> **Stav 2026-06-27:** 3.1–3.4 vyřešeny, 3.5 z velké části doplněna.
> - **3.1 ✅** Produkce běží na HTTPS (Railway), APK je release-podepsané (`key.properties` + CI keystore). Windows exe zůstává nepodepsaný (SmartScreen) — nízká priorita.
> - **3.2 ✅** `STORAGE_DRIVER=s3` vynucený a ověřený živě (`/ready` → `storage.driver=s3`).
> - **3.3 ✅** `backend/.env.production.example` má `CORS_ORIGIN=https://app.example.com`, `ALLOW_WILDCARD_CORS=false`.
> - **3.4 ✅** `git fsck` čistý (žádný corrupt index), staré APK/binárky uklizené z pracovní kopie, `releases/` drží jen poslední 2 verze.
> - **3.5 ◑** Doplněn per-uživatelský rate limit na `POST /api/messages` (60/15 min), `POST /api/sync/push` (300/15 min) a CSV/PDF exporty reportů i pracovních listů (40/15 min) — `security.middleware.ts`. Zbývá zvážit globální limiter na celé `/api`.

| # | Nález | Detail / odkaz |
|---|---|---|
| 3.1 | **HTTP cleartext + nepodepsané buildy** | Beta běží na `http://` (Android `network_security_config.xml` povoluje cleartext), Windows exe nepodepsaný, APK debug-signed bez `key.properties`. Pro produkci nutné HTTPS, odstranit cleartext výjimku, release podpis. Viz `KNOWN_ISSUES.md` §6.2, `RELEASE_CHECKLIST.md` §5. |
| 3.2 | **Fotky na efemérním disku** | `STORAGE_DRIVER=local` na Railway = ztráta fotek při redeployi (přiznáno v `KNOWN_ISSUES.md` §7.2). Produkce musí mít `STORAGE_DRIVER=s3` — konfigurace připravena, ale nevynucuje se. |
| 3.3 | **Produkční šablona doporučuje wildcard CORS** | `backend/.env.production.example` má `CORS_ORIGIN=*` + `ALLOW_WILDCARD_CORS=true` jako výchozí. Pro čistě nativní klienty (Bearer token, žádné cookies) je riziko nízké, ale je to zbytečné oslabení a obchází vlastní pojistku z `config.ts`. |
| 3.4 | **Poškozený git repozitář + 178 necommitnutých změn** | `git fsck` → `index file corrupt`, `improper chunk offset`. Release v1.0.1 tak není reprodukovatelný z čisté historie. Opravit index (`rm .git/index && git reset`), commitnout/uklidit, ověřit push na remote. V kořeni navíc leží 160 MB binárek (2× APK, ZIP) — patří do GitHub Releases, ne do pracovní kopie. |
| 3.5 | **Žádný globální rate limit / lockout mimo login** | Limitovány jsou jen login a `jobs/by-number`. Zprávy (`messages.routes.ts` — spam), sync push, exporty PDF (CPU-náročné: canvas, pdfkit) limit nemají. Pro interní použití OK, pro internet doplnit. |

---

## 4. STŘEDNÍ / DROBNÉ

- **`optionalAuth` je mrtvý kód** a navíc se chová špatně (neplatný token → 401 místo anonymního průchodu) — nikde se nepoužívá, smazat. (`backend/src/middleware/auth.middleware.ts:59-63`)
- **Chybí 404 handler** před `errorMiddleware` → neexistující API cesty vrací výchozí HTML Expressu místo JSON. (`backend/src/app.ts:76`)
- **Node verze není pinovaná** (`engines` v `backend/package.json` chybí) — CI používá Node 20, Railway může mít jinou; s nativními moduly (canvas, sharp, bcrypt) to umí překvapit.
- **`/api/app/release` je bez autentizace** — záměr (update check před loginem), ale prozrazuje URL APK; APK musí být na HTTPS bez citlivého obsahu.
- **Těžké nativní závislosti** (`canvas` 3.2.3 + `sharp` + `pdf-to-img`) — dlouhý build, riziko na Alpine/odlišné glibc; na Railway funguje, ale zdokumentovat.
- **Sync na pozadí Androidu nefunguje spolehlivě** (Doze) — známé omezení, řešeno ručním syncem (`KNOWN_ISSUES.md` §6.4). Pro terénní použití zvážit WorkManager.
- **Worker join přes 8místné číslo stavby** — rate limit 60/15 min/uživatele je rozumná mitigace brute-force; prostor 10⁸ čísel je dostatečný. Bez nálezu, jen zmínka.
- **`bash` vs. souborový pohled na `app.ts` se lišil délkou** — pravděpodobně CRLF/cache artefakt mountu, ne chyba projektu.

## 5. Práva rolí — shrnutí kontroly

Matice (`backend/src/lib/permissions.ts`) je konzistentní s použitím v routách; namátkové integrační testy RBAC existují (`backend/__tests__/rbac.refactor.integration.test.js`, `auth.roles.integration.test.js`, `permissions.test.js`).

> Poznámka 2026-06-27: role **`ucetni` byla odstraněna** (migrace `20250617000000_remove_ucetni_role`), všechna její oprávnění spadla pod `vedeni`. Sloupec `ucetni` v tabulce níže je historický — aktuální role jsou jen **worker / vedeni / admin**.

| Akce | worker | vedeni | ucetni | admin |
|---|---|---|---|---|
| Ucpávky: vytvořit/editovat | ✔ | ✔ | ✖ | ✔ |
| Ucpávky: změna stavu / historie | ✖ | ✔ | ✔ | ✔ |
| Ucpávky: smazat / obnovit | ✖ | ✔ / ✖ | ✖ | ✔ / ✔ |
| Fotky: upload / mazání | ✔ / ✖ | ✔ / ✖ | ✖ | ✔ / ✖ (mazání nemá nikdo) |
| Zakázky, patra, uživatelé, ceník | ✖ | ✔ | ✖ | ✔ |
| Reporty, statistiky, ceník (čtení) | ✔ | ✔ | ✔ | ✔ |
| Výkazy: submit / review / fakturace | ✔/✖/✖ | ✖/✔/✔ | ✖/✖/✔ | ✔ |
| Logy / koš / zálohy | ✖ | ✔/✖/✖ | ✖ | ✔ |

Nesrovnalosti k diskusi (ne nutně chyby):
- `photo.delete: []` — **nikdo** nesmí mazat fotky, ani admin. Záměr (audit trail), nebo opomenutí?
- `worksheet.submit` má worker + admin, ale **ne vedeni**, přestože vedení dělá review — pokud vedení vyplňuje výkaz za workera, nemá ho jak odeslat.
- `seal.edit` zahrnuje workera i pro zamčené stavy jen přes `assertSealEditable` + `statusAfterWorkerEdit` — logika existuje a je testovaná (`seals.http.integration.test.js`), jen upozorňuji, že obchvat zámku má pouze admin (`seal.override_locked`), což je správně.

---

## 6. Checklist před ostrým nasazením (go/no-go)

1. ☑ Upgrade `multer` na 2.x (2.2.0) — `npm audit` lokálně před každým releasem (2.1)
2. ☑ `app.set('trust proxy', 1)` (2.2)
3. ☑ Per-účtový login lockout, min. délka PIN 6, `mustChangePin: true` v seedu (2.3)
4. ☑ HTTPS produkce (Railway); APK release-podepsané. ☐ Windows exe podpis (nízká priorita) (3.1)
5. ☑ Produkce: `STORAGE_DRIVER=s3` (R2), `PUBLIC_UPLOADS=false`, konkrétní `CORS_ORIGIN` (3.2, 3.3)
6. ☑ Git repozitář zdravý, binárky uklizené, `releases/` drží poslední 2 verze (3.4)
7. ☑ **Otestovat obnovu ze zálohy** (pg_dump → restore) — živý test proveden a prošel 2026-06-28 (run [28336839090](https://github.com/Vojtan1995/firemni/actions/runs/28336839090)): dešifrování `.dump.age`, `pg_restore`, FK integritní kontroly i reapply GDPR výmazů bez chyby (20 uživatelů, 10 zakázek, 325 ucpávek, 94 fotek). Detaily v `docs/DR_RUNBOOK.md` → „Záznam o ověření obnovy".
8. ☐ Smoke test celé cesty: login → sync → fotka → export PDF na produkční URL *(průběžně)*

Body 1–6 jsou splněné a produkce je živá → aplikace je způsobilá pro produkční interní nasazení (desítky uživatelů). Zbývají provozní body 7–8. Rate limiting (3.5) je doplněn na nejnáročnější endpointy; globální limiter na celé `/api` zvážit pro veřejné vystavení.
