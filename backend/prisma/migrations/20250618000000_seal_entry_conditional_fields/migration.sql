-- Conditional per-entry fields (Task 3):
--   steel_insulated            – "Doizolováno" (Ano/Ne) for type OCEL
--   electro_installation_type  – Svazek/Husí krk/Žlab for type EL.V. (Elektro)
-- Both nullable so existing rows keep displaying; required only on new/edited entries (app-level).
ALTER TABLE "seal_entries" ADD COLUMN "steel_insulated" BOOLEAN;
ALTER TABLE "seal_entries" ADD COLUMN "electro_installation_type" TEXT;
