Jsi senior Flutter/TypeScript full-stack vývojář. Pracuješ v projektu UNIFAST – aplikace pro evidenci požárních ucpávek, výkresů pater, fotek, soupisů práce, exportů, rolí Worker / Vedení / Účetní / Admin a offline synchronizaci.

Cíl:
Proveď níže popsané úpravy tak, aby aplikace působila profesionálněji, byla praktičtější pro práci s výkresy, měla lepší UX u formulářů, detailu ucpávky a soupisů práce.

---

# POVOLENÍ PRO AGENTA

Máš povolení samostatně provádět změny v projektu v rámci lokálního repozitáře.

Povoluji ti:
- upravovat existující soubory,
- vytvářet nové soubory,
- mazat pouze nepotřebné soubory vzniklé během této práce,
- upravovat Flutter frontend,
- upravovat TypeScript/Express backend,
- upravovat Prisma schema, pokud to bude opravdu nutné,
- přidat migraci databáze, pokud bude pro funkci nezbytná,
- upravovat testy,
- přidávat nové testy,
- spouštět testy,
- spouštět lint/analyze/build,
- instalovat nové balíčky pouze tehdy, pokud je to technicky nutné a lepší než vlastní workaround,
- upravovat UI komponenty a layouty,
- upravovat RBAC kontroly,
- upravovat API endpointy,
- upravovat lokální dokumentaci, pokud to pomůže.

Neptej se na potvrzení u běžných vývojových změn.

Zastav se a zeptej se pouze pokud:
- bys měl smazat větší část existujícího kódu,
- bys měl měnit produkční konfiguraci,
- bys měl měnit produkční databázi,
- bys měl nasazovat na produkci,
- bys měl měnit nebo zobrazovat tajné klíče, tokeny, hesla, .env hodnoty,
- bys měl dělat destruktivní migraci databáze,
- by změna mohla rozbít existující data.

Neprováděj:
- git commit,
- git push,
- deploy na produkci,
- mazání produkčních dat,
- změny secrets,
- změny placené infrastruktury,
pokud to není výslovně zadáno.

---

# OBECNÉ ZÁSADY

- Neprováděj plošný refaktor mimo dotčené části.
- Neměň business logiku, pokud to není nutné.
- Neodstraňuj existující funkce.
- Zachovej existující oprávnění podle rolí.
- Zachovej offline/sync logiku.
- Zachovej relativní ukládání pozic značek na výkresu: x/y vždy 0.0 až 1.0.
- Zachovej originální soubory výkresů.
- Fotky ucpávek mohou zůstat komprimované podle současné logiky.
- Výkresy se nesmí komprimovat stejným způsobem jako fotky ucpávek.
- Po každém větším tasku spusť relevantní testy/analyze.
- Pokud narazíš na problém, oprav ho.
- Zastav se pouze při blokující chybě, kterou nejde bezpečně vyřešit.
- Neplýtvej tokeny dlouhými popisy.
- Piš stručně: co měníš, proč, jak ověřeno.
- Před úpravami si najdi relevantní soubory a zmapuj aktuální stav.

---

# TASK 1 — Výkres: tlačítko Uložit / Pokračovat a čistší pracovní režim

Uprav obrazovku výkresu patra / pracovní stránku výkresu tak, aby se s ní dalo lépe pracovat.

Požadavky:
1. Na pracovní obrazovku výkresu přidej výrazné tlačítko:
   - „Uložit“
   - případně „Uložit a pokračovat“, pokud dává v aktuálním flow větší smysl.
2. Tlačítko má uložit aktuální provedené změny:
   - umístění značek ucpávek,
   - přesuny značek,
   - nové / upravené relativní souřadnice.
3. Po uložení:
   - buď zůstat na výkresu a pokračovat v práci,
   - nebo vrátit uživatele zpět na seznam ucpávek podle aktuálního flow aplikace.
   Vyber bezpečnější UX variantu a zachovej ji konzistentně.
4. V režimu práce s výkresem odeber z horního menu:
   - Oznámení,
   - Zprávy.
5. Ve výkresu má být horní lišta co nejméně rušivá:
   - Zpět,
   - název patra / zakázky,
   - Uložit / Pokračovat,
   - případně Sync status, pokud je důležitý.
6. Neměň horní menu v ostatních částech aplikace.

Akceptační kritéria:
- Ve výkresu už nejsou vidět Oznámení a Zprávy.
- Uživatel má jasné tlačítko pro uložení práce.
- Změny pozic značek se po návratu z výkresu neztratí.
- Relativní souřadnice x/y 0.0–1.0 zůstávají zachované.

---

# TASK 2 — Výkresy: kvalitní podpora PDF a ostrý zoom

Zkontroluj a vylepši podporu PDF výkresů.

Cíl:
Výkres musí být při zoomu co nejčitelnější. PDF nesmí být zbytečně degradované na nízké rozlišení.

Požadavky:
1. Zjisti, jak je nyní řešené zobrazení PDF výkresů.
2. Pokud PDF podpora existuje:
   - ověř, zda PDF není renderované v příliš nízkém rozlišení,
   - uprav render tak, aby při přiblížení zůstával co nejostřejší.
3. Pokud PDF podpora není dostatečná:
   - doplň nebo oprav zobrazení PDF.
4. Priorita:
   - PDF zachovat jako originální soubor.
   - Neprovádět agresivní kompresi PDF výkresů.
   - Pro náhled/render použít vyšší DPI nebo adaptivní render podle zoomu, ale rozumně kvůli výkonu a RAM.
5. U obrázkových výkresů:
   - PNG/JPG/JPEG zachovat v originální kvalitě.
   - Nepoužívat stejnou kompresi jako u fotek ucpávek.
6. Pokud je obrázek menší než 2500 px na šířku, ponech nebo doplň varování:
   „Výkres má nízké rozlišení a při přiblížení může být rozmazaný.“
7. Neřeš ostrost tak, že se bude vše renderovat extrémním rozlišením a aplikace bude padat na paměti.
8. Pokud je PDF vektorové, snaž se využít výhod vektorového renderu. Pokud knihovna renderuje do bitmapy, použij rozumně vyšší DPI / tile rendering / cache podle možností projektu.
9. Pokud je pro kvalitu zobrazení lepší PDF předem nebo průběžně renderovat do obrazu, udělej to, ale bezpečně:
   - renderuj PDF ve vyšším rozlišení než běžný náhled,
   - preferuj adaptivní render podle zoomu nebo tile rendering, pokud to použitá knihovna umožňuje,
   - nepřeváděj originální PDF natrvalo na nízké rozlišení,
   - originální PDF vždy zachovej,
   - vyrenderované bitmapy používej pouze jako cache / pracovní náhled,
   - cache řeš tak, aby se dala obnovit z originálního PDF,
   - hlídej RAM a výkon na mobilu,
   - při velkých PDF nepoužívej extrémní jednorázový render celé stránky, který může shodit aplikaci.
10. Ideální chování:
   - při běžném zobrazení použít rozumný náhled,
   - při zoomu postupně dorenderovat ostřejší verzi,
   - při posunu po výkresu nerenderovat zbytečně celé PDF znovu,
   - značky ucpávek musí zůstat umístěné podle relativních souřadnic nad vyrenderovaným podkladem.
11. Pokud aktuální knihovna neumí kvalitní adaptivní render nebo tile rendering:
   - zvol nejlepší dostupnou variantu,
   - nastav vyšší DPI / scale factor,
   - přidej komentář do výstupu, jaké omezení knihovna má,
   - navrhni případnou lepší knihovnu nebo technické řešení do budoucna.

Akceptační kritéria:
- PDF výkres lze otevřít.
- Zoom je znatelně čitelnější než při nízkém bitmapovém náhledu.
- Aplikace nespadne při běžném zoomování.
- Originální PDF zůstává zachované.
- Umístění značek na PDF funguje stejně jako u obrázku.
- Pokud je PDF renderované do bitmapy, používá se dostatečně vysoké rozlišení pro čitelný zoom.
- Originální PDF se neztrácí a není nahrazené nekvalitním obrázkem.
- Render/cache nesmí způsobovat pády aplikace kvůli paměti.
- Značky ucpávek sedí správně nad PDF i po renderu, zoomu a návratu na obrazovku.

---

# TASK 3 — Formulář ucpávky: menší mezery, lepší výchozí hodnoty

Uprav formulář pro vytváření/editaci ucpávky.

Problém:
Formulář má zbytečně velké mezery, velké odstupy a působí nataženě. Navíc nejsou předvyplněná ani předvybraná žádná pole, takže pracovník musí zbytečně klikat.

Požadavky:
1. Zmenši vertikální mezery mezi poli, sekcemi a tlačítky.
2. Zmenši paddingy tam, kde jsou přehnané.
3. Formulář musí působit kompaktněji, ale pořád čitelně na mobilu.
4. U tlačítek/chipů voleb:
   - zmenši zbytečně velké výšky,
   - sjednoť velikost,
   - udělej je přehledné.
5. Přidej rozumné výchozí hodnoty / předvýběry:
   - typické hodnoty vyber podle aktuální logiky aplikace a existujících možností,
   - pokud je k dispozici poslední použitá hodnota pracovníka, preferuj ji,
   - jinak nastav bezpečné defaulty.
6. Předvyplnění nesmí způsobit chybné ukládání.
7. Uživatel musí pořád jasně vidět, co je vybrané.
8. Povinná pole musí být validovaná jako doteď.

Doporučené defaulty, pokud v projektu neexistuje lepší logika:
- počet kusů: 1,
- odolnost: nejběžnější hodnota podle existující aplikace, případně 90,
- umístění: žádné nebo nejčastější, pokud je bezpečné,
- konstrukce: žádné nebo nejčastější, pokud je bezpečné,
- izolace: žádné / „není“ pouze pokud to nezkresluje data.
U materiálu a systému buď opatrný — nepředvybírej konkrétní výrobek, pokud by to mohlo vést ke špatné evidenci.

Akceptační kritéria:
- Formulář je kratší a kompaktnější.
- Zbytečné mezery jsou odstraněné.
- Některé bezpečné hodnoty jsou předvyplněné.
- Validace funguje.
- Editace existující ucpávky nepřepisuje uložené hodnoty defaulty.

---

# TASK 4 — Soupisy práce: vedení a účetní vidí pracovníky a jejich soupisy

Uprav sekci Soupisy práce pro role Vedení a Účetní.

Cíl:
Vedení a účetní mají mít přehled podle pracovníků. Po otevření pracovníka uvidí jeho vytvořené soupisy.

Požadavky:
1. Pro role Vedení a Účetní zobraz v sekci Soupisy práce seznam pracovníků.
2. U každého pracovníka zobraz základní informaci:
   - jméno / username,
   - počet soupisů,
   - případně počet čekajících / odevzdaných / schválených soupisů, pokud data existují.
3. Po otevření pracovníka zobraz jeho soupisy.
4. U soupisů zachovej existující možnosti:
   - otevřít detail,
   - stáhnout/exportovat,
   - filtrovat podle zakázky/stavu/období, pokud už existuje,
   - pro vedení měnit stav, pokud to aplikace už umožňuje.
5. Worker nesmí vidět seznam všech pracovníků.
6. Worker dál vidí pouze svoje soupisy podle aktuálního oprávnění.
7. Účetní a vedení dál vidí všechna potřebná data.
8. Pokud backend endpoint už existuje, použij ho.
9. Pokud endpoint chybí, doplň bezpečně nový endpoint s RBAC kontrolou.
10. Nezaváděj duplicitní logiku, pokud lze využít existující model soupisů.

Akceptační kritéria:
- Vedení vidí seznam pracovníků.
- Účetní vidí seznam pracovníků.
- Po kliknutí na pracovníka se zobrazí jeho soupisy.
- Worker seznam pracovníků nevidí.
- RBAC na backendu nepustí workera k cizím datům.
- Existující exporty/soupisy zůstanou funkční.

---

# TASK 5 — Detail ucpávky: profesionální redesign

Navrhni a implementuj lepší vzhled detailu ucpávky.

Problém:
Detail ucpávky nyní působí nahodile/random. Má vypadat jako profesionální firemní aplikace.

Požadavky:
1. Přepracuj detail ucpávky do jasných sekcí:
   - Hlavička,
   - Stav,
   - Základní údaje,
   - Rozměry / prostupy,
   - Materiály a systém,
   - Fotografie,
   - Poznámka,
   - Historie / audit,
   - Akce podle role.
2. Hlavička má obsahovat:
   - číslo ucpávky,
   - zakázku,
   - patro,
   - aktuální stav,
   - autora / poslední úpravu, pokud data existují.
3. Stav zobraz jako profesionální badge:
   - Rozpracováno,
   - Zkontrolováno,
   - Fakturováno,
   - Vráceno k opravě, pokud existuje.
4. Hodnoty zobraz v přehledných řádcích nebo kartách:
   - label vlevo,
   - hodnota vpravo,
   - žádné rozházené texty bez struktury.
5. Fotky zobraz jako čistou galerii:
   - jednotné náhledy,
   - možnost otevřít detail fotky, pokud už existuje,
   - bez rozbitého layoutu.
6. Akční tlačítka rozděl podle role:
   - Worker: upravit, přidat foto, případně pokračovat.
   - Vedení: schválit, vrátit k opravě, fakturovat, vrátit na rozpracované.
   - Účetní: hlavně náhled/export/fakturační relevantní údaje podle existující logiky.
7. Neblokuj existující workflow.
8. Nepřidávej akce, které nejsou backendově podporované.
9. Pokud některá data nejsou k dispozici, zobraz kultivovaně „Neuvedeno“ místo prázdných/random hodnot.
10. Styl drž podle aktuálního designu aplikace:
   - tmavé UI,
   - bílé texty,
   - červené akcenty,
   - firemní/profesionální vzhled.

Akceptační kritéria:
- Detail ucpávky působí jako hotová profesionální obrazovka.
- Data jsou jasně členěná.
- Akce jsou přehledné a podle role.
- Nezhorší se editace, fotky ani status workflow.
- Layout funguje na mobilu i menší obrazovce.

---

# TASK 6 — Testování a kontrola

Po implementaci proveď kontrolu.

Spusť podle možností projektu:
- Flutter analyze
- Flutter test
- Backend TypeScript build
- Backend testy
- případně konkrétní testy pro RBAC / soupisy / výkresy

Minimálně ověř ručně nebo testem:
1. Worker:
   - otevře formulář ucpávky,
   - vidí kompaktnější formulář,
   - uloží ucpávku,
   - nevidí seznam pracovníků v soupisech.
2. Vedení:
   - otevře výkres,
   - nevidí ve výkresu Oznámení/Zprávy,
   - uloží změny pozic značek,
   - otevře soupisy podle pracovníků,
   - otevře detail ucpávky s novým layoutem.
3. Účetní:
   - vidí seznam pracovníků v soupisech,
   - otevře jejich soupisy,
   - nemá nepovolené administrační akce.
4. PDF:
   - PDF výkres se otevře,
   - zoom je čitelný,
   - značky sedí i po přiblížení.

Na konci vypiš:
- seznam změněných souborů,
- co bylo implementováno,
- co bylo otestováno,
- případné riziko nebo technický dluh,
- zda je potřeba migrace databáze,
- zda je potřeba rebuild APK.
