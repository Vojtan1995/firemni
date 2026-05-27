const { execSync } = require('child_process');
const path = require('path');
const { ensureTestDatabase } = require('./ensureTestDatabase.cjs');

const backendDir = path.resolve(__dirname, '../..');
const testDatabaseUrl =
  process.env.TEST_DATABASE_URL ||
  'postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky_test';

module.exports = async function globalSetup() {
  const env = {
    ...process.env,
    DATABASE_URL: testDatabaseUrl,
    NODE_ENV: 'test',
  };

  console.log('\n[globalSetup] ensure database ucpavky_test');
  try {
    await ensureTestDatabase();
  } catch (err) {
    console.error(
      '[globalSetup] Nelze vytvořit test DB. Spusťte docs/setup-local-postgres-test.sql jako postgres',
    );
    console.error('  nebo nastavte POSTGRES_ADMIN_URL (superuser).');
    throw err;
  }

  console.log('[globalSetup] migrate deploy → ucpavky_test');
  execSync('npx prisma migrate deploy', { cwd: backendDir, env, stdio: 'inherit' });

  console.log('[globalSetup] db seed → ucpavky_test');
  execSync('npx prisma db seed', { cwd: backendDir, env, stdio: 'inherit' });
};
