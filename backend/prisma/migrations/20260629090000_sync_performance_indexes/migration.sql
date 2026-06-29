CREATE INDEX IF NOT EXISTS "jobs_updated_at_idx" ON "jobs"("updated_at");

CREATE INDEX IF NOT EXISTS "job_floors_job_id_updated_at_idx"
  ON "job_floors"("job_id", "updated_at");

CREATE INDEX IF NOT EXISTS "floor_drawings_updated_at_idx"
  ON "floor_drawings"("updated_at");

CREATE INDEX IF NOT EXISTS "seal_photos_seal_id_created_at_deleted_at_idx"
  ON "seal_photos"("seal_id", "created_at", "deleted_at");
