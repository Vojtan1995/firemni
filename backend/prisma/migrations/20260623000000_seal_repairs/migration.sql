-- Modul Oprava: samostatný evidenční záznam navázaný na původní ucpávku.
-- Aditivní migrace — žádná stávající tabulka se nemění.
CREATE TABLE "seal_repairs" (
    "id" TEXT NOT NULL,
    "seal_id" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "floor_id" TEXT NOT NULL,
    "seal_number" TEXT NOT NULL,
    "note" TEXT NOT NULL,
    "original_snapshot" JSONB NOT NULL,
    "repair_data" JSONB NOT NULL,
    "changed_fields" JSONB,
    "created_by_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "seal_repairs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "seal_repairs_seal_id_idx" ON "seal_repairs"("seal_id");
CREATE INDEX "seal_repairs_job_id_idx" ON "seal_repairs"("job_id");
CREATE INDEX "seal_repairs_created_by_id_idx" ON "seal_repairs"("created_by_id");
CREATE INDEX "seal_repairs_created_at_idx" ON "seal_repairs"("created_at");

ALTER TABLE "seal_repairs" ADD CONSTRAINT "seal_repairs_seal_id_fkey" FOREIGN KEY ("seal_id") REFERENCES "seals"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "seal_repairs" ADD CONSTRAINT "seal_repairs_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "jobs"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "seal_repairs" ADD CONSTRAINT "seal_repairs_floor_id_fkey" FOREIGN KEY ("floor_id") REFERENCES "job_floors"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "seal_repairs" ADD CONSTRAINT "seal_repairs_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
