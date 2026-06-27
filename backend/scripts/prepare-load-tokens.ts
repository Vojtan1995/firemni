import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { prisma } from '../src/lib/prisma.js';
import { createAuthenticatedSession } from '../src/services/session.service.js';

const count = Number(process.env.LOAD_WORKERS || 50);
const output = path.resolve(process.env.LOAD_TOKEN_FILE || '../reports/load-tokens.json');

async function main() {
  if (process.env.NODE_ENV === 'production' || process.env.ALLOW_LOAD_TOKENS !== '1') {
    throw new Error('Token preparation requires NODE_ENV!=production and ALLOW_LOAD_TOKENS=1');
  }
  if (!Number.isInteger(count) || count < 1 || count > 100) {
    throw new Error('LOAD_WORKERS must be an integer between 1 and 100');
  }
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET === 'dev-secret-change-me') {
    throw new Error('JWT_SECRET must equal the staging backend JWT_SECRET');
  }

  const users = await prisma.user.findMany({
    where: { username: { startsWith: 'load_worker_' }, isActive: true },
    orderBy: { username: 'asc' },
  });
  const byNumber = new Map(
    users.map((user) => [Number(user.username.replace('load_worker_', '')), user]),
  );
  const tokens: string[] = [];
  for (let index = 1; index <= count; index++) {
    const user = byNumber.get(index);
    if (!user) throw new Error(`Missing load_worker_${index}; run seed:load first`);
    const session = await createAuthenticatedSession(user.id, 'pin');
    tokens.push(session.token);
  }
  await writeFile(output, JSON.stringify({ createdAt: new Date().toISOString(), tokens }, null, 2), {
    encoding: 'utf8',
    mode: 0o600,
  });
  console.log(`Created ${tokens.length} staging sessions in ${output}`);
  console.log('The file contains bearer tokens. Delete it after the test.');
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
