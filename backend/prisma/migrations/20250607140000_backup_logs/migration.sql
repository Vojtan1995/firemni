CREATE TABLE "backup_logs" (
    "id" TEXT NOT NULL,
    "file_name" TEXT NOT NULL,
    "file_path" TEXT NOT NULL,
    "file_size_bytes" BIGINT,
    "status" TEXT NOT NULL,
    "error_message" TEXT,
    "triggered_by" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "backup_logs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "backup_logs_created_at_idx" ON "backup_logs"("created_at");
