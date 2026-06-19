# SYNC.md – Offline-first synchronizace

## Offline-first princip

1. Data uložit lokálně (Drift SQLite) okamžitě po akci uživatele
2. Vytvořit outbox mutaci s unikátním `mutationId`
3. Pokus o sync při dostupnosti sítě
4. Při chybě nikdy neztratit data – mutace zůstane ve frontě

## Lokální DB

Drift (SQLite) na klientovi. Umístění:
- **Windows:** `%USERPROFILE%\Documents\ucpavky.db`
- **Android:** app-private storage

---

## local_outbox – stavy

| Stav | Popis |
|------|-------|
| `pending` | Čeká na odeslání |
| `sending` | Právě odesíláno |
| `failed` | Dočasná chyba sítě, bude zkuseno znovu |
| `done` | Server potvrdil zpracování |
| `conflict` | Konflikt – vyžaduje manuální řešení uživatelem |

---

## Push endpoint

**`POST /api/sync/push`**

Odesílá batch mutací. Každá mutace má tvar:

```json
{
  "mutationId": "uuid-v4",
  "deviceId": "string",
  "entityType": "seal | sealEntry | sealStatus | photo",
  "operation": "create | update | delete",
  "payload": { ... },
  "baseVersion": 3
}
```

- `mutationId` je **unikátní** (UNIQUE index v `sync_mutations`) – zaručuje idempotenci
- `baseVersion` = verze entity, ze které klient vychází (detekce konfliktu)
- Server vrátí seznam výsledků: `{ mutationId, status: "ok" | "conflict", conflictReason? }`

### Payload pro `entityType: "seal"` (create)

```json
{
  "localId": "...",
  "sealNumber": 1,
  "floorId": "uuid",
  "jobId": "uuid",
  "entries": [
    {
      "entryType": "kabel",
      "dimension": "M25",
      "quantity": 2,
      "insulation": false,
      "materials": ["Intumex L"]
    }
  ]
}
```

---

## Pull endpoint

**`GET /api/sync/pull?since=<ISO_timestamp>&deviceId=<id>`**

Vrací:
- Všechny změny entit od `since` (updatedAt > since)
- Conflict markery pro mutace tohoto zařízení, které servery odmítly

---

## Versioning

Každá ucpávka (seal) nese:
- `version` – čítač, inkrementuje se při každém update
- `updated_at` – ISO timestamp poslední změny
- `updated_by` – ID uživatele

Klient posílá `baseVersion`. Pokud server má vyšší verzi, vrátí `conflict`.

---

## Retry logika

| Pokus | Čekání před dalším pokusem |
|-------|---------------------------|
| 1. selhání | 30 s |
| 2. selhání | 2 min |
| 3. a další | 5 min |

---

## Typy konfliktů

| Typ | Příčina |
|-----|---------|
| Duplicitní číslo ucpávky | Jiný pracovník vytvořil ucpávku se stejným číslem na stejném patře |
| Concurrent edit | Někdo jiný upravil ucpávku, `version` se liší |
| Zamčená ucpávka | Ucpávka není ve stavu `draft` (worker nemůže editovat) |
| Archivovaná/smazaná stavba | Job byl archivován nebo smazán, nové ucpávky nelze přidat |

---

## Kritická pravidla

- Nikdy neztratit lokální data (ani při konfliktu)
- Nikdy automaticky nepřepsat konflikt bez vědomí uživatele
- Server musí být idempotentní přes `mutationId` – opakované poslání stejné mutace nemá vedlejší efekty
