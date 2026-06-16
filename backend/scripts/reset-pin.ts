/**
 * Údržbový skript: reset PINu uživatele + zrušení lockoutu.
 *
 * Bez argumentů vypíše seznam uživatelů (najdeš svůj username).
 * S argumenty resetuje PIN konkrétního uživatele na 6–8 číslic.
 *
 * Pracuje proti databázi v DATABASE_URL — pro produkci spouštěj přes
 * `railway run ...` (injektuje produkční DATABASE_URL), nebo dočasně
 * nastav DATABASE_URL na produkční connection string.
 *
 * Použití:
 *   npx tsx scripts/reset-pin.ts                      # vypíše uživatele
 *   npx tsx scripts/reset-pin.ts <username> <pin6-8>  # resetuje PIN
 */
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  const username = process.argv[2] ?? process.env.RESET_USERNAME;
  const pin = process.argv[3] ?? process.env.RESET_PIN;

  if (!username) {
    const users = await prisma.user.findMany({
      select: { username: true, displayName: true, role: true, isActive: true },
      orderBy: { username: 'asc' },
    });
    console.log(`\nUživatelé v této databázi (${users.length}):`);
    for (const u of users) {
      const flag = u.isActive ? '' : ' (neaktivní)';
      console.log(`  - ${u.username}  [${u.role}]${flag} — ${u.displayName}`);
    }
    if (users.length === 0) {
      console.log('  (žádní uživatelé — databáze není naseedovaná)');
    }
    console.log(
      '\nReset PINu: npx tsx scripts/reset-pin.ts <username> <novyPin(6-8 číslic)>',
    );
    return;
  }

  if (!pin || !/^\d{6,8}$/.test(pin)) {
    throw new Error('Nový PIN musí mít 6 až 8 číslic.');
  }

  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) {
    throw new Error(
      `Uživatel "${username}" v databázi neexistuje. Spusť skript bez argumentů pro seznam.`,
    );
  }

  const pinHash = await bcrypt.hash(pin, 10);
  await prisma.user.update({
    where: { id: user.id },
    data: { pinHash, mustChangePin: true, isActive: true },
  });

  // Vyčisti neúspěšné pokusy → zruší případný account lockout.
  const cleared = await prisma.loginLog.deleteMany({
    where: { username, success: false },
  });

  console.log(`\n✅ PIN uživatele "${username}" (${user.role}) byl resetován.`);
  console.log(`   nový PIN: ${pin}`);
  console.log('   mustChangePin: true — po přihlášení si nastav vlastní PIN');
  console.log(`   zrušeno ${cleared.count} neúspěšných pokusů (lockout)`);
}

main()
  .catch((e) => {
    console.error('Chyba:', e instanceof Error ? e.message : e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
