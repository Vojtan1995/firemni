-- Task 7/9: snapshot of seal data + price list version on each worksheet item,
-- so prices/contents stay locked even if the seal or price list later changes.
ALTER TABLE "worksheet_items" ADD COLUMN "system" TEXT;
ALTER TABLE "worksheet_items" ADD COLUMN "insulation" TEXT;
ALTER TABLE "worksheet_items" ADD COLUMN "location" TEXT;
ALTER TABLE "worksheet_items" ADD COLUMN "catalog_id" TEXT;
ALTER TABLE "worksheet_items" ADD COLUMN "price_list_version" TEXT;
