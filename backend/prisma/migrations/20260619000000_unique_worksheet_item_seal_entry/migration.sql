-- Tvrdá pojistka proti dvojí fakturaci: jeden prostup (SealEntry) smí být
-- nejvýše v jednom soupisu. Aplikační kontrola (worksheet.service.ts) běží
-- read-then-write a neochrání proti souběhu requestů, proto unikátnost vynutí
-- i databáze. WorkSheetItem nemá soft-delete, takže stačí prostý unique index.
CREATE UNIQUE INDEX "worksheet_items_seal_entry_id_key" ON "worksheet_items"("seal_entry_id");
