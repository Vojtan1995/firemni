-- CreateEnum
CREATE TYPE "MaterialMode" AS ENUM ('with_material', 'without_material');

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "material_mode" "MaterialMode" NOT NULL DEFAULT 'without_material';

-- Rozdělení ceníku na dvě ceny: dnešní ceny odpovídají variantě "bez materiálu".
-- Nejprve zkopírovat stávající cenu do sloupce bez materiálu, poté vynulovat cenu s materiálem.
UPDATE "price_list_items" SET "price_without_material" = "price_with_material";
UPDATE "price_list_items" SET "price_with_material" = 0;
