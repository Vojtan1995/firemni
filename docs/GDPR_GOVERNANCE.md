# GDPR governance a retenční politika

Tento dokument je technická šablona. Právní tituly, retenční lhůty business
evidence a smlouvy musí schválit správce osobních údajů nebo jeho poradce.

## ROPA

| Kategorie | Účel | Subjekty | Příjemci | Výchozí retence | Výmaz/export |
|---|---|---|---|---|---|
| Účet, role | řízení přístupu | zaměstnanci | vedení/admin | trvání účtu + schválená lhůta | anonymizace / privacy export |
| Login IP a user-agent | ochrana účtu | uživatelé | admin | 90 dní | automatická retence |
| Error a sync log | provoz a diagnostika | uživatelé | vedení/admin/Sentry | 90 dní | automatická retence |
| Zprávy | interní komunikace | uživatelé | odesílatel/příjemce | 365 dní | retence/anonymizace |
| Notifikace | pracovní workflow | uživatelé | daný uživatel | 180 dní | retence/anonymizace |
| Ucpávky, opravy, audit | požární a smluvní evidence | pracovníci | oprávněné role/zákazník v exportu | DOPLNIT A SCHVÁLIT | anonymizované autorství |
| Fotografie a plány | technická dokumentace | případně zachycené osoby | oprávněné role | DOPLNIT A SCHVÁLIT | řízený proces |
| Soupisy a ceny | výkon/fakturace | pracovníci | vedení | DOPLNIT A SCHVÁLIT | zákonná/smluvní politika |
| DB backup | kontinuita | všechny DB subjekty | DR správci | 30–35 dní | expirace + replay erasure ledgeru |

## Zpracovatelé

Před produkčním schválením doplnit DPA, region, subprocessory, přenos mimo EHP,
retenci a exit postup pro Railway, Cloudflare, GitHub, Sentry, UptimeRobot a
Telegram. Telegram alert nesmí obsahovat osobní ani business data.

## Práva subjektu

- export: `GET /api/users/:id/privacy-export` (admin + čerstvé MFA),
- výmaz/anonymizace: `DELETE /api/users/:id`,
- evidence výmazů: `privacy_erasures`,
- informace: `GET/POST /api/privacy/notice`,
- po obnově zálohy se musí znovu aplikovat aktuální erasure ledger.

## Privacy notice

Aplikace eviduje pracovní účet, role, aktivitu, technické záznamy, fotografie,
zprávy, notifikace a bezpečnostní logy pro provoz, audit a dokumentaci požárních
ucpávek. Uživatelé nesmí bez nezbytného pracovního důvodu fotografovat osoby,
doklady, SPZ ani jiné osobní údaje. Úplný interní informační dokument musí být
publikován na URL v `PRIVACY_NOTICE_URL`.

## Incident

1. Zachovat logy a omezit kompromitovaný přístup.
2. Informovat vlastníka bezpečnosti a správce osobních údajů.
3. Zjistit kategorie, osoby, rozsah, dobu a dopad.
4. Zapsat časovou osu a nápravná opatření.
5. Správce rozhodne o oznamovací povinnosti a komunikaci.
6. Rotovat kompromitované secrets a revokovat sessions.
7. Provést post-incident review.
