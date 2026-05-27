-- Lokální PostgreSQL setup pro projekt Ucpávky (Windows)
-- Spusťte jako superuser (typicky postgres), např. přes pgAdmin Query Tool nebo psql.

-- 1) Role (uživatel) pro aplikaci
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'ucpavky') THEN
    CREATE ROLE ucpavky WITH LOGIN PASSWORD 'ucpavky_dev';
  END IF;
END
$$;

-- 2) Databáze
-- Pokud DB už existuje, tento příkaz selže – to je v pořádku.
CREATE DATABASE ucpavky OWNER ucpavky;

-- 3) Oprávnění (pro jistotu, pokud DB existovala dříve)
GRANT ALL PRIVILEGES ON DATABASE ucpavky TO ucpavky;

-- Ověření (volitelné):
-- \l
-- \du
