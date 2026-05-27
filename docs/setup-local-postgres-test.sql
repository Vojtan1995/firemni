-- Testovací databáze pro backend integrační testy (BE-01+)
-- Spusťte jako superuser (postgres), např. pgAdmin Query Tool.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'ucpavky') THEN
    CREATE ROLE ucpavky WITH LOGIN PASSWORD 'ucpavky_dev';
  END IF;
END
$$;

-- Umožní roli vytvořit test DB při npm test (ensureTestDatabase), pokud DB ještě neexistuje
ALTER ROLE ucpavky CREATEDB;

-- Pokud DB už existuje, příkaz selže – to je v pořádku.
CREATE DATABASE ucpavky_test OWNER ucpavky;

GRANT ALL PRIVILEGES ON DATABASE ucpavky_test TO ucpavky;
