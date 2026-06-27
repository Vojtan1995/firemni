ALTER TABLE "users" ADD COLUMN "password_hash" TEXT;

ALTER TABLE "user_sessions"
  ADD COLUMN "mfa_verified_at" TIMESTAMP(3),
  ADD COLUMN "auth_method" TEXT NOT NULL DEFAULT 'pin';

CREATE TABLE "user_mfa_credentials" (
  "id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "secret_ciphertext" TEXT NOT NULL,
  "key_version" INTEGER NOT NULL DEFAULT 1,
  "enabled_at" TIMESTAMP(3),
  "last_used_step" BIGINT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "user_mfa_credentials_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "user_mfa_credentials_user_id_key"
  ON "user_mfa_credentials"("user_id");

ALTER TABLE "user_mfa_credentials"
  ADD CONSTRAINT "user_mfa_credentials_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "mfa_recovery_codes" (
  "id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "code_hash" TEXT NOT NULL,
  "used_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "mfa_recovery_codes_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "mfa_recovery_codes_user_id_used_at_idx"
  ON "mfa_recovery_codes"("user_id", "used_at");

ALTER TABLE "mfa_recovery_codes"
  ADD CONSTRAINT "mfa_recovery_codes_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "auth_challenges" (
  "id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "token_hash" TEXT NOT NULL,
  "kind" TEXT NOT NULL,
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "consumed_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "auth_challenges_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "auth_challenges_token_hash_key"
  ON "auth_challenges"("token_hash");
CREATE INDEX "auth_challenges_user_id_created_at_idx"
  ON "auth_challenges"("user_id", "created_at");
CREATE INDEX "auth_challenges_expires_at_idx"
  ON "auth_challenges"("expires_at");

ALTER TABLE "auth_challenges"
  ADD CONSTRAINT "auth_challenges_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "privacy_notice_acceptances" (
  "id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "version" TEXT NOT NULL,
  "accepted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "privacy_notice_acceptances_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "privacy_notice_acceptances_user_id_version_key"
  ON "privacy_notice_acceptances"("user_id", "version");

ALTER TABLE "privacy_notice_acceptances"
  ADD CONSTRAINT "privacy_notice_acceptances_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "privacy_erasures" (
  "id" TEXT NOT NULL,
  "subject_user_id" TEXT NOT NULL,
  "actor_user_id" TEXT NOT NULL,
  "original_username_hash" TEXT NOT NULL,
  "details" JSONB,
  "performed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "privacy_erasures_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "privacy_erasures_performed_at_idx"
  ON "privacy_erasures"("performed_at");
