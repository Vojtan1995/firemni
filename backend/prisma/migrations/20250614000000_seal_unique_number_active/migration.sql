-- Partial unique index: zabraňuje duplicitnímu číslu ucpávky na stejném patře
-- mezi aktivními (nesmazanými) ucpávkami. Pojistka proti race condition v
-- checkDuplicateSealNumber (read-then-write). Soft-delete řádky jsou vyloučeny,
-- takže lze opětovně použít číslo po smazání.
CREATE UNIQUE INDEX "seal_unique_number_active"
  ON "seals" ("job_id", "floor_id", "seal_number")
  WHERE "deleted_at" IS NULL;
