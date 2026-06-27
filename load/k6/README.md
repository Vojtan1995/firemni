# Penetrační a kapacitní test

Testy jsou určené pouze pro izolovaný staging se syntetickými daty a písemným
oprávněním. Každý aktivní nástroj vyžaduje potvrzovací proměnnou a přesnou shodu
`TARGET_HOST` s hostem v `BASE_URL`; host obsahující `prod` nebo `production`
je automaticky odmítnut.

## 1. Příprava dat

Staging musí mít stejný Railway, PostgreSQL a R2 plán jako produkce. Seed je
opakovatelný, používá stabilní UUID a rozděluje pracovníky mezi stavby, aby šlo
testovat izolaci dat.

```powershell
$env:NODE_ENV='staging'
$env:ALLOW_LOAD_SEED='1'
$env:DATABASE_URL='postgresql://...staging...'
$env:LOAD_JOBS='50'
$env:LOAD_SEALS_PER_FLOOR='500'
$env:LOAD_WORKERS='50'
cd backend
npm run seed:load
```

Výchozí PIN syntetických pracovníků je `654321`. Seed má pojistky maximálně
100 staveb, 500 ucpávek na patro a 100 pracovníků.

## 2. Bezpečnostní smoke a IDOR test

```powershell
$env:BASE_URL='https://staging.example.com'
$env:TARGET_HOST='staging.example.com'
$env:ALLOW_SECURITY_TEST='YES'
$env:LOAD_PIN='654321'
node security/active-api-smoke.mjs
```

Test ověřuje anonymní přístup, vadný JWT, horizontální IDOR mezi dvěma
pracovníky, enumeraci uživatelů, strop sync dávky, poškozený upload, security
hlavičky a CORS. Pro odeslání payloadu těsně nad 15 MB nastavte navíc
`TEST_UPLOAD_LIMITS=YES`.

Autentizovaný OWASP ZAP full scan:

```powershell
$env:ALLOW_SECURITY_TEST='YES'
.\security\run-zap.ps1 `
  -BaseUrl 'https://staging.example.com' `
  -TargetHost 'staging.example.com' `
  -BearerToken '<časově omezený staging token>'
```

ZAP reporty vzniknou v `reports/`. Token musí patřit syntetickému účtu a po
testu se má session odhlásit nebo odstranit.

## 3. k6 profily

Nainstalujte k6, vytvořte adresář reportů a nastavte společné proměnné:

```powershell
New-Item -ItemType Directory -Force reports | Out-Null
$env:BASE_URL='https://staging.example.com'
$env:TARGET_HOST='staging.example.com'
$env:ALLOW_LOAD_TEST='YES'
$env:LOAD_PIN='654321'
$env:LOAD_WORKERS='50'
```

Pro profily nad 20 VU připravte session tokeny mimo HTTP login limiter. Příkaz
vyžaduje staging `DATABASE_URL` a stejný `JWT_SECRET`, jaký používá staging API:

```powershell
cd backend
$env:NODE_ENV='staging'
$env:ALLOW_LOAD_TOKENS='1'
$env:LOAD_TOKEN_FILE='..\reports\load-tokens.json'
npm run prepare:load-tokens
cd ..
$env:TOKEN_FILE=(Resolve-Path 'reports\load-tokens.json').Path
```

Soubor obsahuje platné bearer tokeny, nesmí se commitovat a po testu se smaže.
Bez `TOKEN_FILE` se každý VU přihlásí přes API; to je vhodné pouze pro baseline
a samostatné měření autentizace, protože login limiter je 30 pokusů/IP/15 min.

Profily spouštějte samostatně a mezi nimi nechte prostředí alespoň 10 minut
ustálit:

```powershell
$env:PROFILE='baseline'; k6 run load/k6/main.js
$env:PROFILE='load';     k6 run load/k6/main.js
$env:PROFILE='stress';   k6 run load/k6/main.js
$env:PROFILE='spike';    k6 run load/k6/main.js
$env:PROFILE='soak'
$env:SOAK_VUS='50'
$env:SOAK_DURATION='2h'
k6 run load/k6/main.js
```

Každý virtuální uživatel se přihlásí jen jednou. Běžný mix zahrnuje stavby,
patra, seznam ucpávek, dashboard, search a sync pull/push. Výsledky se zapisují
do `reports/k6-<profil>.json` a `.md`.

### Uploady a exporty

Měří se odděleně, aby CPU/R2 špička nezakryla limit běžného API:

```powershell
$env:PROFILE='heavy'
$env:LOAD_USERNAME='load_worker_1'
$env:PHOTO_PATH='C:\fixtures\photo-5mb.jpg'
$env:SEAL_ID='<přístupné UUID ucpávky>'
$env:JOB_ID='<přístupné UUID stavby s 2000 ucpávkami>'
k6 run load/k6/heavy.js
```

Admin MFA smoke používá čerstvý TOTP kód:

```powershell
$env:PROFILE='admin-mfa'
$env:ADMIN_USERNAME='admin-load'
$env:ADMIN_PASSWORD='<heslo>'
$env:ADMIN_TOTP_CODE='<aktuální kód>'
k6 run load/k6/admin-mfa.js
```

## 4. Limity a stop podmínky

SLO běžného API: read p95 do 1 s, write/sync p95 do 1,5 s a chybovost pod 1 %.
Upload p95 má být do 10 s; PDF export 2 000 ucpávek do 30 s.

Test ručně zastavte při kterékoli podmínce:

- chybovost alespoň 5 % po dvě minuty nebo p95 alespoň 5 s;
- restart instance, vyčerpání DB spojení nebo trvalý růst paměti;
- poškození či nekonzistence dat;
- nedostupnost `/ready`, která se po snížení zátěže neobnoví.

Během každého stupně zaznamenejte Railway CPU/RAM/restarty, PostgreSQL spojení
a pomalé dotazy, R2 odezvu, commit a velikost datasetu. Za kapacitu se považuje
poslední stabilní stupeň splňující SLO, nikoli nejvyšší krátce dosažená špička.

## 5. Kontrola po testu

```powershell
cd backend
$env:NODE_ENV='staging'
$env:ALLOW_LOAD_VERIFY='1'
$env:DATABASE_URL='postgresql://...staging...'
npm run verify:load
```

Kontrola selže při duplicitních číslech aktivních ucpávek, osiřelých entries,
nedokončených k6 sync mutacích, chybějících patrech nebo účastnících.
Nakonec ověřte `/ready`, storage audit a odhlaste testovací sessions.

## Interpretace reportu

Finální protokol musí uvést poslední vyhovující a první nevyhovující stupeň,
RPS, počet VU, p50/p95/p99, chybovost, čas zotavení a první saturovaný zdroj.
Výsledek je přenositelný na produkci pouze při shodné velikosti služeb,
konfiguraci, datasetu a externích závislostech.
