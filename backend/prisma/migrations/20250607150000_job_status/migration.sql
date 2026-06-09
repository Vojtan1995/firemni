CREATE TYPE "JobStatus" AS ENUM ('active', 'completed', 'archived');

ALTER TABLE "jobs" ADD COLUMN "status" "JobStatus" NOT NULL DEFAULT 'active';

UPDATE "jobs" SET "status" = 'archived' WHERE "is_archived" = true;

CREATE INDEX "jobs_status_idx" ON "jobs"("status");
