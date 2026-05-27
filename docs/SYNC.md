# SYNC.md

## Offline-first princip
1. data uložit lokálně
2. vytvořit outbox mutaci
3. pokus o sync
4. při chybě nikdy neztratit data

## Lokální DB
Použít SQLite přes Drift.

## local_outbox
Statusy:
- pending
- sending
- failed
- done
- conflict

## Konflikty
Řešit:
- duplicitní číslo ucpávky
- editaci entity změněné někým jiným
- editaci zamčené ucpávky
- archivovanou/smazanou stavbu

## Push endpoint
POST /api/sync/push

## Pull endpoint
GET /api/sync/pull

## Versioning
Každá ucpávka:
- version
- updated_at
- updated_by

Klient posílá baseVersion.

## Retry logika
- retry po 30 s
- potom 2 min
- potom 5 min

## Kritická pravidla
- nikdy neztratit lokální data
- nikdy automaticky nepřepsat konflikt
- server musí být idempotentní přes mutationId
