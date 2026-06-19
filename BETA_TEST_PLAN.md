# BETA_TEST_PLAN.md – interní beta (1–2 pracovníci)

Plán ručního testování pro **interní betu V1**.  
Checklist release: [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) · Spuštění: [RUNNING.md](RUNNING.md).

---

## 1. Cíl a rozsah

| Položka | Hodnota |
|---------|---------|
| **Účel** | Ověřit worker flow v terénu, offline/sync, management export |
| **Testeri** | 1–2 pracovníci (doporučeno: 1× worker, 1× vedení) |
| **Délka** | 1–2 pracovní dny |
| **Platforma** | Windows release **nebo** Android APK (ne obojí nutně) |
| **Backend** | Lokální PC v kanceláři / notebook na stavbě (Wi‑Fi/LAN) |

**Mimo rozsah bety:** push notifikace, ceník, diskuze, web klient, koš pro patra/stavby.

---

## 2. Příprava prostředí (správce IT)

### Backend (na PC, který bude v síti dostupný)

```powershell
cd c:\Users\vojte\Desktop\unifast\backend
# .env: DATABASE_URL, JWT_SECRET
npx prisma migrate deploy
npx prisma db seed
npm run dev
```

Ověření: `Invoke-WebRequest http://localhost:3000/health` → 200.

**Poznámka:** Pro Android telefon na stejné Wi‑Fi zjistěte IP PC (`ipconfig`) a při buildu APK použijte  
`--dart-define=API_BASE_URL=http://192.168.x.x:3000`, nebo na emulátoru `adb reverse tcp:3000 tcp:3000`.

### Seed účty (PIN všude `123456`, 6 číslic)

| Uživatel | Role | Použití v betě |
|----------|------|----------------|
| `worker1` | worker | hlavní terénní scénáře |
| `vedeni` | management | soupis, export, změna statusu |
| `admin` | admin | koš, obnova ucpávky |

Testovací stavba: číslo **`12345678`**, patra ze seedu (např. `1. NP`, `2. NP`).

---

## 3. Instalace pro testery

### Varianta A – Windows (doporučeno v kanceláři)

1. Dostat složku `Release\` (celá, ne jen exe) – viz [RUNNING.md](RUNNING.md) §5.2.
2. Backend musí běžet na tomto PC nebo v LAN na `http://<IP>:3000`.
3. Spustit `ucpavky.exe`.
4. Při SmartScreen zvolit **Spustit přesto** (nepodepsaný build).

### Varianta B – Android telefon

1. Nainstalovat `app-release.apk` (povolit neznámé zdroje).
2. Telefon a PC se serverem ve **stejné Wi‑Fi**.
3. Správce sdělí IP backendu; APK musí být sestavené s touto URL (nebo použít emulátor + `adb reverse`).
4. Ověřit v aplikaci login – pokud „síťová chyba“, špatná API URL.

---

## 4. Testovací scénáře

Označte: ✅ prošlo · ❌ selhalo · ⏭ přeskočeno · poznámka

### 4.1 Přihlášení a menu (oba testeri)

| ID | Kroky | Očekávání |
|----|--------|-----------|
| T1 | Spustit app, přihlásit `worker1` / `123456` | Hlavní menu, položka **Stavba** |
| T2 | Odhlásit, přihlásit `vedeni` / `123456` | Menu management (soupis, stavby…) |
| T3 | Špatný PIN | Chybová hláška, žádný token |

### 4.2 Worker – základní flow (`worker1`)

| ID | Kroky | Očekávání |
|----|--------|-----------|
| W1 | Stavba → `12345678` | Načtou se patra |
| W2 | Vybrat patro → seznam ucpávek | Seznam (může být prázdný) |
| W3 | Nová ucpávka – vyplnit povinná pole, uložit | Ucpávka v seznamu |
| W4 | Otevřít detail ucpávky | Detail, fotky/metadata dle zadání |
| W5 | Přidat fotku (pokud zařízení podporuje) | Náhled / fronta upload |

### 4.3 Offline a sync (`worker1`)

| ID | Kroky | Očekávání |
|----|--------|-----------|
| O1 | Vypnout Wi‑Fi / odpojit síť | App nepadá |
| O2 | Vytvořit ucpávku offline | Uloženo lokálně |
| O3 | Sync obrazovka | Položka ve stavu **pending** |
| O4 | Zapnout síť → **Synchronizovat** | Pending zmizí / úspěch |
| O5 | (volitelně) Konflikt – pokud vznikne | Zobrazení na Sync, bez tichého smazání |

### 4.4 Management (`vedeni`)

| ID | Kroky | Očekávání |
|----|--------|-----------|
| M1 | Soupis práce – filtr stavba/status | Tabulka / přehled |
| M2 | Export **CSV** | Soubor uložen, cesta ve zprávě |
| M3 | Export **PDF** | Soubor uložen, otevřitelný PDF |
| M4 | Změna statusu ucpávky (draft → checked) | Úspěch |
| M5 | Worker nemá export v menu | Worker účet bez soupisu |

### 4.5 Admin (volitelně, krátký test)

| ID | Kroky | Očekávání |
|----|--------|-----------|
| A1 | Přihlásit `admin`, otevřít **Koš** | Seznam smazaných ucpávek |
| A2 | Obnovit ucpávku | Znovu v seznamu na patře |

---

## 5. Hlášení problémů

Pro každý ❌ vyplňte:

```text
ID scénáře:
Platforma: Windows / Android (model):
Backend: IP:port nebo localhost:
Kroky:
Očekávání:
Skutečnost:
Screenshot / čas:
```

Kritické (blokující práci): okamžitě správci IT.  
Ostatní: seznam po skončení dne.

---

## 6. Kritéria úspěchu bety

| Kritérium | Požadavek |
|-----------|-----------|
| Worker flow W1–W4 | alespoň 1 tester ✅ |
| Offline O2–O4 | alespoň 1 tester ✅ |
| Management M2 nebo M3 | ✅ u `vedeni` |
| Žádná ztráta dat po sync | žádný kritický bug |
| Crash při běžné práci | 0 výskytů |

---

## 7. Po skončení

- [ ] Vyplněné tabulky scénářů odevzdány správci
- [ ] Aktualizace [KNOWN_ISSUES.md](KNOWN_ISSUES.md) dle nálezů
- [ ] Rozhodnutí: druhá beta kolo / přechod na hostovaný backend

---

## Kontakty (doplňte před betou)

| Role | Jméno | Kontakt |
|------|-------|---------|
| Správce backendu / DB | | |
| Správce sítě (LAN, firewall) | | |
| Vývoj / eskalace | | |
