-- Price list + entry price snapshot (PRICE-01 / PRICE-SNAPSHOT-01)

CREATE TABLE "price_lists" (
    "id" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "valid_from" TIMESTAMP(3) NOT NULL,
    "valid_to" TIMESTAMP(3),
    "active" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "price_lists_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "price_lists_version_key" ON "price_lists"("version");

CREATE TABLE "price_list_items" (
    "id" TEXT NOT NULL,
    "price_list_id" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "size_label" TEXT NOT NULL,
    "unit" TEXT NOT NULL DEFAULT 'kus',
    "price_with_material" DECIMAL(10,2) NOT NULL,
    "price_without_material" DECIMAL(10,2),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "sort_order" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "price_list_items_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "price_list_items_price_list_id_category_idx" ON "price_list_items"("price_list_id", "category");

ALTER TABLE "price_list_items" ADD CONSTRAINT "price_list_items_price_list_id_fkey" FOREIGN KEY ("price_list_id") REFERENCES "price_lists"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "seal_entries" ADD COLUMN "unit_price" DECIMAL(10,2),
ADD COLUMN "total_price" DECIMAL(10,2),
ADD COLUMN "currency" TEXT DEFAULT 'CZK',
ADD COLUMN "price_list_version" TEXT,
ADD COLUMN "price_list_item_id" TEXT,
ADD COLUMN "price_mode" TEXT,
ADD COLUMN "priced_at" TIMESTAMP(3),
ADD COLUMN "priced_by_user_id" TEXT,
ADD COLUMN "price_source" TEXT;

ALTER TABLE "seal_entries" ADD CONSTRAINT "seal_entries_price_list_item_id_fkey" FOREIGN KEY ("price_list_item_id") REFERENCES "price_list_items"("id") ON DELETE SET NULL ON UPDATE CASCADE;
