import { prisma } from '../src/lib/prisma.js';
import { resetMfa } from '../src/services/mfa.service.js';

function arg(name: string) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function main() {
  const username = arg('username');
  const actorUsername = arg('actor');
  if (!username || !actorUsername) {
    throw new Error('Usage: npm run mfa:reset -- --username TARGET --actor ADMIN');
  }
  if (process.env.CONFIRM_MFA_RESET !== username) {
    throw new Error('Set CONFIRM_MFA_RESET exactly to the target username');
  }
  const [target, actor] = await Promise.all([
    prisma.user.findUnique({ where: { username } }),
    prisma.user.findUnique({ where: { username: actorUsername } }),
  ]);
  if (!target || target.role !== 'admin') throw new Error('Target admin not found');
  if (!actor || actor.role !== 'admin' || !actor.isActive) {
    throw new Error('Active actor admin not found');
  }
  if (target.id === actor.id) throw new Error('Actor and target must be different admins');
  await resetMfa(actor.id, target.id);
  console.log(`MFA reset for ${username}; all target sessions revoked`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
