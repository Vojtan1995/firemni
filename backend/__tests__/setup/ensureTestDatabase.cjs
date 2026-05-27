const { Client } = require('pg');

/**
 * Vytvoří ucpavky_test, pokud neexistuje.
 * POSTGRES_ADMIN_URL = připojení jako superuser (výchozí: stejný user na DB postgres).
 */
async function ensureTestDatabase() {
  const testDatabaseUrl =
    process.env.TEST_DATABASE_URL ||
    'postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky_test';

  const testUrl = new URL(testDatabaseUrl);
  const dbName = testUrl.pathname.replace(/^\//, '');
  const owner = decodeURIComponent(testUrl.username);

  const adminUrl =
    process.env.POSTGRES_ADMIN_URL ||
    `${testUrl.protocol}//${testUrl.username}:${testUrl.password}@${testUrl.hostname}:${testUrl.port || 5432}/postgres`;

  const client = new Client({ connectionString: adminUrl });
  await client.connect();
  try {
    const { rows } = await client.query(
      'SELECT 1 FROM pg_database WHERE datname = $1',
      [dbName],
    );
    if (rows.length === 0) {
      await client.query(`CREATE DATABASE "${dbName}" OWNER "${owner}"`);
      console.log(`[ensureTestDatabase] vytvořena databáze ${dbName}`);
    }
  } finally {
    await client.end();
  }
}

module.exports = { ensureTestDatabase };
