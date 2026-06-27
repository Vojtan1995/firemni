-- DropForeignKey
ALTER TABLE "seal_repairs" DROP CONSTRAINT "seal_repairs_seal_id_fkey";

-- AddForeignKey
ALTER TABLE "seal_repairs" ADD CONSTRAINT "seal_repairs_seal_id_fkey" FOREIGN KEY ("seal_id") REFERENCES "seals"("id") ON DELETE CASCADE ON UPDATE CASCADE;
