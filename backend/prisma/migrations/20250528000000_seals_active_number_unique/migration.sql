-- Partial unique: číslo ucpávky unikátní na patře mezi aktivními (nesmazanými) záznamy.
-- Viz docs/DATABASE.md
CREATE UNIQUE INDEX "seals_active_number_unique"
ON "seals" ("job_id", "floor_id", "seal_number")
WHERE "deleted_at" IS NULL;
