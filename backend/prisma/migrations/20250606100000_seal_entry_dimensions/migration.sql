-- Volitelný rozměr celého prostupu na ucpávce
ALTER TABLE "seals" ADD COLUMN "opening_length_mm" INTEGER;
ALTER TABLE "seals" ADD COLUMN "opening_width_mm" INTEGER;

-- Rozšíření prostupu o rozměry, výpočty a jednotku
ALTER TABLE "seal_entries" ADD COLUMN "item_length_mm" INTEGER;
ALTER TABLE "seal_entries" ADD COLUMN "item_width_mm" INTEGER;
ALTER TABLE "seal_entries" ADD COLUMN "calculated_area_m2" DECIMAL(12,6);
ALTER TABLE "seal_entries" ADD COLUMN "calculated_linear_meters" DECIMAL(12,6);
ALTER TABLE "seal_entries" ADD COLUMN "calculated_net_area_m2" DECIMAL(12,6);
ALTER TABLE "seal_entries" ADD COLUMN "unit" TEXT;

-- quantity: Int -> Decimal (zachování stávajících hodnot)
ALTER TABLE "seal_entries" ALTER COLUMN "quantity" DROP DEFAULT;
ALTER TABLE "seal_entries" ALTER COLUMN "quantity" TYPE DECIMAL(12,3) USING "quantity"::decimal;
ALTER TABLE "seal_entries" ALTER COLUMN "quantity" SET DEFAULT 1;

-- worksheet_items snapshot quantity
ALTER TABLE "worksheet_items" ALTER COLUMN "quantity" DROP DEFAULT;
ALTER TABLE "worksheet_items" ALTER COLUMN "quantity" TYPE DECIMAL(12,3) USING "quantity"::decimal;
ALTER TABLE "worksheet_items" ALTER COLUMN "quantity" SET DEFAULT 1;
