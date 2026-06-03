-- Job participants and private messages (phase 2).
CREATE TABLE IF NOT EXISTS "job_participants" (
  "id" TEXT NOT NULL,
  "job_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "role_on_job" TEXT NOT NULL,
  "assigned_by_id" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "last_activity_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "job_participants_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "job_participants_job_id_user_id_key"
  ON "job_participants"("job_id", "user_id");

ALTER TABLE "job_participants"
  ADD CONSTRAINT "job_participants_job_id_fkey"
  FOREIGN KEY ("job_id") REFERENCES "jobs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "job_participants"
  ADD CONSTRAINT "job_participants_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE IF NOT EXISTS "private_messages" (
  "id" TEXT NOT NULL,
  "sender_id" TEXT NOT NULL,
  "recipient_id" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "read_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "private_messages_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "private_messages_recipient_id_read_at_idx"
  ON "private_messages"("recipient_id", "read_at");

ALTER TABLE "private_messages"
  ADD CONSTRAINT "private_messages_sender_id_fkey"
  FOREIGN KEY ("sender_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "private_messages"
  ADD CONSTRAINT "private_messages_recipient_id_fkey"
  FOREIGN KEY ("recipient_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
