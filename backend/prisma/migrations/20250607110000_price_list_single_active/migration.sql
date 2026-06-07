-- At most one active price list (H-06)
UPDATE "price_lists"
SET "active" = false
WHERE "active" = true
  AND "id" NOT IN (
    SELECT "id"
    FROM "price_lists"
    WHERE "active" = true
    ORDER BY "created_at" DESC
    LIMIT 1
  );

CREATE UNIQUE INDEX "price_lists_one_active_idx"
  ON "price_lists" ((true))
  WHERE "active" = true;
