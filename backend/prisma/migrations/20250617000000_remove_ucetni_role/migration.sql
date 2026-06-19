-- Remove the 'ucetni' (administrativa) role.
-- 1) Migrate any existing ucetni users to vedeni.
-- 2) Drop the 'ucetni' value from the UserRole enum by recreating the type.

UPDATE "users" SET "role" = 'vedeni' WHERE "role" = 'ucetni';

ALTER TYPE "UserRole" RENAME TO "UserRole_old";

CREATE TYPE "UserRole" AS ENUM ('worker', 'vedeni', 'admin');

ALTER TABLE "users"
  ALTER COLUMN "role" TYPE "UserRole"
  USING ("role"::text::"UserRole");

DROP TYPE "UserRole_old";
