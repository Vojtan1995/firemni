-- Soupisy "pro zákazníka" jsou jen informativní (nic se nefakturuje), proto
-- jeden prostup (SealEntry) může být ve více zákaznických soupisech. Globální
-- unikát na seal_entry_id se nahrazuje ČÁSTEČNÝM indexem, který platí jen pro
-- fakturovatelné (audience='worker') soupisy – tam zůstává pojistka proti dvojí
-- fakturaci (1 prostup = nejvýše 1 worker soupis).

-- 1) Denormalizovaný audience na položce soupisu (default 'worker').
ALTER TABLE "worksheet_items" ADD COLUMN "audience" TEXT NOT NULL DEFAULT 'worker';

-- 2) Backfill z rodičovského soupisu.
UPDATE "worksheet_items" wi
SET "audience" = w."audience"
FROM "worksheets" w
WHERE wi."worksheet_id" = w."id";

-- 3) Nahradit globální unikát částečným (jen pro worker soupisy).
DROP INDEX "worksheet_items_seal_entry_id_key";
CREATE UNIQUE INDEX "worksheet_items_seal_entry_worker_key"
  ON "worksheet_items"("seal_entry_id")
  WHERE "audience" = 'worker';
