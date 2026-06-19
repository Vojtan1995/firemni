# DATABASE.md – Schéma databáze

PostgreSQL 16. ORM: Prisma 6. Migrace: `npx prisma migrate deploy`.

---

## Enums

| Enum | Hodnoty |
|------|---------|
| `UserRole` | `worker`, `vedeni`, `ucetni`, `admin` |
| `SealStatus` | `draft`, `checked`, `invoiced` |
| `WorkSheetStatus` | `draft`, `submitted`, `reviewed`, `ready_for_invoice`, `invoiced` |
| `JobStatus` | `active`, `completed`, `archived` |

---

## Tabulky

### Uživatelé a session

| Tabulka | Popis |
|---------|-------|
| `users` | Přihlašovací údaje, role (`UserRole`), `pinHash` (bcrypt), `isActive`, `mustChangePin` |
| `user_sessions` | JWT sessions – `token` (hash), `expiresAt`, `userId` |
| `login_log` | Záznamy pokusů o přihlášení: IP, user agent, `success` flag |

### Stavby a patra

| Tabulka | Popis |
|---------|-------|
| `jobs` | Stavba: `projectNumber` (8 číslic, unique), název, adresa, `status` (`JobStatus`), soft delete |
| `job_floors` | Patro: název, `sortOrder`, FK → job, soft delete |
| `floor_drawings` | Plán patra (PNG/JPG nahrávka) – 1:1 s `job_floors` (unique per floor) |
| `job_participants` | Přiřazení pracovníků ke stavbě – M:N (userId × jobId) |

### Ucpávky

| Tabulka | Popis |
|---------|-------|
| `seals` | Ucpávka: `sealNumber`, `status` (`SealStatus`), `version` (pro sync), FK → floor/job/user, soft delete |
| `seal_entries` | Položky ucpávky: `entryType`, dimension, quantity, insulation, FK → seal |
| `seal_entry_materials` | Materiály na položku: M:N (entryId × material string) |
| `seal_photos` | Metadata fotek: path, mime, size, FK → seal. **Mazání je zakázáno** (403) – zachování audit trail |
| `seal_markers` | Pozice ucpávky na plánu patra: `x`, `y` (normalizované 0–1), FK → seal + floor_drawing |

### Sync a audit

| Tabulka | Popis |
|---------|-------|
| `sync_mutations` | Offline sync fronta: `mutationId` (UNIQUE), `deviceId`, `entityType`, `operation`, `payload` (JSON), `processedAt` |
| `activity_log` | Akce uživatelů: `entityType`, `entityId`, `action`, metadata (JSON) |
| `change_log` | Změny na úrovni polí: `field`, `oldValue`, `newValue`, `changedAt`, `changedById` |
| `error_log` | Chyby serveru: stack, path, method, statusCode |

### Komunikace a notifikace

| Tabulka | Popis |
|---------|-------|
| `private_messages` | Zprávy mezi uživateli: `senderId`, `recipientId`, `body`, `readAt` |
| `notification` | Notifikace: `type`, `title`, `body`, `entityType`, `entityId`, `readAt`, FK → user |

### Ceník

| Tabulka | Popis |
|---------|-------|
| `price_list` | Verze ceníku: `version` (číslo), `publishedAt`, `publishedById` |
| `price_list_items` | Položky ceníku: penetration type, size range, unit price, FK → price_list |

### Pracovní listy (Worksheets)

| Tabulka | Popis |
|---------|-------|
| `worksheet` | Pracovní list: název, `status` (`WorkSheetStatus`), FK → job |
| `worksheet_worker` | Přiřazení pracovníků k listu – M:N |
| `worksheet_item` | Ucpávky v pracovním listu: FK → seal + worksheet |

### Operační záznamy

| Tabulka | Popis |
|---------|-------|
| `backup_log` | Záznamy záloh DB: `triggeredAt`, `triggeredById`, `filePath`, `status` |

---

## Kritický unikátní index

```sql
UNIQUE (job_id, floor_id, seal_number) WHERE deleted_at IS NULL
```

Zabraňuje duplicitním číslům ucpávek na stejném patře. Server vrátí `409 Conflict` při porušení.

---

## Pravidla integrity

| Pravidlo | Implementace |
|----------|-------------|
| Žádný hard delete | Soft delete: `deletedAt`, `deletedById`, `deleteReason` |
| Worker edituje pouze draft | API vrátí `403` pokud `status != 'draft'` a role je `worker` |
| Fotky nelze smazat | `DELETE /api/photos/:id` vrací `403` (audit trail) |
| Sync idempotence | `sync_mutations.mutationId` je UNIQUE – opakovaný push je bez efektu |
| Verzování ucpávek | `seals.version` se inkrementuje při každém update, `baseVersion` v push požadavku detekuje konflikt |
| Session hash | `user_sessions.token` je uložen jako hash (ne plaintext JWT) |

---

## Foto storage

Metadata (path, mime, size, hash) jsou v DB v tabulce `seal_photos`.
Fyzické soubory jsou mimo DB:

| Prostředí | Storage |
|-----------|---------|
| Vývoj | `backend/uploads/` (local filesystem) |
| Produkce | S3-kompatibilní object storage (Cloudflare R2 nebo AWS S3) – `STORAGE_DRIVER=s3` |

Přístup k fotkám: `GET /api/photos/:id/file` (vyžaduje autentizaci, kontroluje autorizaci).

---

## Lokální setup

```powershell
# Vytvoření vývojové DB (jednorázově)
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres -f "C:\Users\vojte\Desktop\unifast\docs\setup-local-postgres.sql"

# Vytvoření testovací DB (pro npm test)
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -U postgres -f "C:\Users\vojte\Desktop\unifast\docs\setup-local-postgres-test.sql"

# Migrace a seed
cd C:\Users\vojte\Desktop\unifast\backend
npx prisma migrate deploy
npx prisma db seed
```
