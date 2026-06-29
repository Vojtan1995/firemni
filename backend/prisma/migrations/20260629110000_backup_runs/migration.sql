CREATE TABLE "backup_runs" (
  "id" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "github_run_url" TEXT,
  "r2_prefix" TEXT,
  "manifest_key" TEXT,
  "bytes" BIGINT,
  "object_count" INTEGER,
  "error_message" TEXT,
  "started_at" TIMESTAMP(3),
  "finished_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "backup_runs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "backup_runs_type_created_at_idx" ON "backup_runs"("type", "created_at");
CREATE INDEX "backup_runs_status_created_at_idx" ON "backup_runs"("status", "created_at");
