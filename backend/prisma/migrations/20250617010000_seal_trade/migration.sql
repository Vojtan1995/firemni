-- Add mandatory Řemeslo (trade) field to seals and worksheet items.
CREATE TYPE "SealTrade" AS ENUM ('elektrikari', 'vzduchari', 'vodari', 'topenari', 'plynari', 'ostatni', 'neurceno');

ALTER TABLE "seals" ADD COLUMN "trade" "SealTrade" NOT NULL DEFAULT 'neurceno';
ALTER TABLE "worksheet_items" ADD COLUMN "trade" "SealTrade" NOT NULL DEFAULT 'neurceno';
