-- M-02: query performance indexes
CREATE INDEX IF NOT EXISTS "seals_created_by_id_idx" ON "seals"("created_by_id");
CREATE INDEX IF NOT EXISTS "seals_updated_at_idx" ON "seals"("updated_at");
CREATE INDEX IF NOT EXISTS "seals_job_id_updated_at_idx" ON "seals"("job_id", "updated_at");
CREATE INDEX IF NOT EXISTS "seal_entries_seal_id_idx" ON "seal_entries"("seal_id");
CREATE INDEX IF NOT EXISTS "seal_photos_seal_id_idx" ON "seal_photos"("seal_id");
CREATE INDEX IF NOT EXISTS "job_floors_job_id_idx" ON "job_floors"("job_id");
CREATE INDEX IF NOT EXISTS "login_log_created_at_idx" ON "login_log"("created_at");
CREATE INDEX IF NOT EXISTS "sync_mutations_user_id_created_at_idx" ON "sync_mutations"("user_id", "created_at");
CREATE INDEX IF NOT EXISTS "activity_log_user_id_created_at_idx" ON "activity_log"("user_id", "created_at");
CREATE INDEX IF NOT EXISTS "job_participants_user_id_idx" ON "job_participants"("user_id");
