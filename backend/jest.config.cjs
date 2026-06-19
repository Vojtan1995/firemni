/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'node',
  setupFiles: ['<rootDir>/__tests__/setup/env.cjs'],
  globalSetup: '<rootDir>/__tests__/setup/globalSetup.cjs',
  globalTeardown: '<rootDir>/__tests__/setup/globalTeardown.cjs',
  testMatch: ['**/__tests__/**/*.test.js'],
  testPathIgnorePatterns: ['/node_modules/', '/setup/'],
  testTimeout: 30000,
  verbose: true,
};
