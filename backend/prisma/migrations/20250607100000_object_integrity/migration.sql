-- Worksheet item unit snapshot + FK integrity
ALTER TABLE "worksheet_items" ADD COLUMN IF NOT EXISTS "unit" TEXT;

UPDATE "worksheet_items" wi
SET "unit" = se."unit"
FROM "seal_entries" se
WHERE wi."seal_entry_id" = se."id" AND wi."unit" IS NULL;

UPDATE "worksheet_items" SET "unit" = 'kus' WHERE "unit" IS NULL;

ALTER TABLE "worksheet_items"
  ADD CONSTRAINT "worksheet_items_floor_id_fkey"
  FOREIGN KEY ("floor_id") REFERENCES "job_floors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "worksheet_items"
  ADD CONSTRAINT "worksheet_items_worker_id_fkey"
  FOREIGN KEY ("worker_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Seal floor must belong to seal job (trigger; CHECK cannot use subqueries in PostgreSQL)
CREATE OR REPLACE FUNCTION "seals_floor_belongs_to_job_fn"()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "job_floors" f
    WHERE f."id" = NEW."floor_id" AND f."job_id" = NEW."job_id"
  ) THEN
    RAISE EXCEPTION 'Patro nepatří k zakázce ucpávky';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "seals_floor_belongs_to_job" ON "seals";
CREATE TRIGGER "seals_floor_belongs_to_job"
  BEFORE INSERT OR UPDATE OF "job_id", "floor_id" ON "seals"
  FOR EACH ROW
  EXECUTE FUNCTION "seals_floor_belongs_to_job_fn"();
