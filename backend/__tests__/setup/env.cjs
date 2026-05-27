// Nastavení prostředí před načtením modulů aplikace (oddělená test DB).
const testDatabaseUrl =
  process.env.TEST_DATABASE_URL ||
  'postgresql://ucpavky:ucpavky_dev@localhost:5432/ucpavky_test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = testDatabaseUrl;
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-for-integration';
process.env.UPLOAD_PATH = process.env.UPLOAD_PATH || './uploads-test';
process.env.CORS_ORIGIN = '*';
