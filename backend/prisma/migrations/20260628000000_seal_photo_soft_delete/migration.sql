-- AlterTable: měkké smazání fotek (soft-delete + audit), soubor v úložišti zůstává
ALTER TABLE "seal_photos" ADD COLUMN     "deleted_at" TIMESTAMP(3),
ADD COLUMN     "deleted_by_id" TEXT,
ADD COLUMN     "delete_reason" TEXT;

-- CreateIndex
CREATE INDEX "seal_photos_seal_id_deleted_at_idx" ON "seal_photos"("seal_id", "deleted_at");

-- AddForeignKey
ALTER TABLE "seal_photos" ADD CONSTRAINT "seal_photos_deleted_by_id_fkey" FOREIGN KEY ("deleted_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
