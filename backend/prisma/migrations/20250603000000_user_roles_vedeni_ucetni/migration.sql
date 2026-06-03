-- Rename management role to vedeni and add ucetni role.
ALTER TYPE "UserRole" RENAME VALUE 'management' TO 'vedeni';
ALTER TYPE "UserRole" ADD VALUE IF NOT EXISTS 'ucetni';
