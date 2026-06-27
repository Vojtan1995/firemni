import bcrypt from 'bcrypt';
import { v4 as uuidv4 } from 'uuid';
import { createHash } from 'node:crypto';
import { User, UserRole, MaterialMode, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';
import { VEDENI_ROLES } from '../lib/permissions.js';
import { assertStrongAdminPassword } from './mfa.service.js';

export const MANAGEMENT_ROLES = VEDENI_ROLES;

const ASSIGNABLE_BY_VEDENI: UserRole[] = [UserRole.worker, UserRole.vedeni];

export type PublicUser = {
  id: string;
  username: string;
  displayName: string;
  role: UserRole;
  materialMode: MaterialMode;
  isActive: boolean;
  mustChangePin: boolean;
  createdAt: Date;
  updatedAt: Date;
};

export function toPublicUser(user: User): PublicUser {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    role: user.role,
    materialMode: user.materialMode,
    isActive: user.isActive,
    mustChangePin: user.mustChangePin,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  };
}

function assertRoleAssignable(actorRole: UserRole, role: UserRole) {
  if (actorRole === UserRole.admin) return;
  if (role === UserRole.admin || !ASSIGNABLE_BY_VEDENI.includes(role)) {
    throw forbidden('Vedení nemůže spravovat účty s rolí admin');
  }
}

function assertCanManageTarget(actorRole: UserRole, target: User) {
  if (actorRole === UserRole.admin) return;
  if (target.role === UserRole.admin) {
    throw forbidden('Vedení nemůže upravovat administrátorské účty');
  }
}

export async function listUsers(actorRole?: UserRole): Promise<PublicUser[]> {
  const users = await prisma.user.findMany({ orderBy: { username: 'asc' } });
  const filtered =
    actorRole === UserRole.admin
      ? users
      : users.filter((u) => u.role !== UserRole.admin);
  return filtered.map(toPublicUser);
}

export async function createUser(
  actorRole: UserRole,
  data: {
    username: string;
    displayName: string;
    pin: string;
    role: UserRole;
    materialMode?: MaterialMode;
  },
): Promise<PublicUser> {
  assertRoleAssignable(actorRole, data.role);

  const existing = await prisma.user.findUnique({ where: { username: data.username } });
  if (existing) throw badRequest('Uživatelské jméno již existuje');

  if (data.role === UserRole.admin) assertStrongAdminPassword(data.pin);
  const credentialHash = await bcrypt.hash(data.pin, 10);
  const lockedPinHash =
    data.role === UserRole.admin
      ? await bcrypt.hash(uuidv4() + uuidv4(), 10)
      : credentialHash;
  const user = await prisma.user.create({
    data: {
      username: data.username,
      displayName: data.displayName,
      pinHash: lockedPinHash,
      passwordHash: data.role === UserRole.admin ? credentialHash : null,
      role: data.role,
      materialMode: data.materialMode ?? MaterialMode.without_material,
      mustChangePin: true,
    },
  });
  return toPublicUser(user);
}

export async function updateUser(
  actorRole: UserRole,
  actorId: string,
  userId: string,
  data: Partial<{
    displayName: string;
    pin: string;
    role: UserRole;
    isActive: boolean;
    materialMode: MaterialMode;
  }>,
): Promise<PublicUser> {
  const target = await prisma.user.findUnique({ where: { id: userId } });
  if (!target) throw notFound('Uživatel nenalezen');

  assertCanManageTarget(actorRole, target);

  if (data.role !== undefined) {
    assertRoleAssignable(actorRole, data.role);
  }

  if (data.isActive === false && userId === actorId) {
    throw badRequest('Nelze deaktivovat vlastní účet');
  }

  const updateData: {
    displayName?: string;
    pinHash?: string;
    role?: UserRole;
    isActive?: boolean;
    mustChangePin?: boolean;
    materialMode?: MaterialMode;
    passwordHash?: string | null;
  } = {};

  if (data.displayName !== undefined) updateData.displayName = data.displayName;
  if (data.role !== undefined) updateData.role = data.role;
  if (data.isActive !== undefined) updateData.isActive = data.isActive;
  if (data.materialMode !== undefined) updateData.materialMode = data.materialMode;
  if (data.pin !== undefined) {
    const finalRole = data.role ?? target.role;
    if (finalRole === UserRole.admin) {
      assertStrongAdminPassword(data.pin);
      updateData.passwordHash = await bcrypt.hash(data.pin, 10);
    } else {
      updateData.pinHash = await bcrypt.hash(data.pin, 10);
    }
    updateData.mustChangePin = true;
  }
  if (data.role === UserRole.admin && target.role !== UserRole.admin && data.pin === undefined) {
    throw badRequest('Při povýšení na admina je nutné nastavit heslo');
  }

  if (Object.keys(updateData).length === 0) {
    throw badRequest('Žádná pole k úpravě');
  }

  const user = await prisma.user.update({ where: { id: userId }, data: updateData });

  if (data.isActive === false || data.pin !== undefined) {
    await prisma.userSession.deleteMany({ where: { userId } });
  }

  return toPublicUser(user);
}

const ANONYMIZED_USERNAME_PREFIX = 'deleted_';

export function isAnonymizedUser(user: Pick<User, 'username'>) {
  return user.username.startsWith(ANONYMIZED_USERNAME_PREFIX);
}

/**
 * GDPR „právo na výmaz". Uživatele odkazuje mnoho business tabulek (ucpávky,
 * audit, soupisy práce), proto se účet fyzicky nemaže, ale **anonymizuje** –
 * osobní údaje (jméno, IP v login logu, soukromé zprávy, notifikace, sezení)
 * se odstraní, business záznamy zůstanou pod anonymním účtem „Smazaný uživatel".
 * Audit (ActivityLog / ChangeLog) zůstává, jen se v něm jméno zobrazí anonymně.
 * Pouze admin.
 */
export async function anonymizeUser(
  actorRole: UserRole,
  actorId: string,
  userId: string,
): Promise<void> {
  if (actorRole !== UserRole.admin) {
    throw forbidden('Anonymizaci osobních údajů může provést pouze administrátor');
  }
  if (userId === actorId) {
    throw badRequest('Nelze anonymizovat vlastní účet');
  }

  const target = await prisma.user.findUnique({ where: { id: userId } });
  if (!target) throw notFound('Uživatel nenalezen');
  if (isAnonymizedUser(target)) {
    throw badRequest('Uživatel je již anonymizovaný');
  }

  // Neplatný, ale validní bcrypt hash – na účet se už nikdy nikdo nepřihlásí.
  const lockedPinHash = await bcrypt.hash(uuidv4() + uuidv4(), 10);
  const originalUsernameHash = createHash('sha256').update(target.username).digest('hex');

  await prisma.$transaction([
    // login log obsahuje IP adresu, user agent a username = osobní údaj
    prisma.loginLog.deleteMany({
      where: { OR: [{ userId }, { username: target.username }] },
    }),
    prisma.userSession.deleteMany({ where: { userId } }),
    prisma.notification.deleteMany({ where: { userId } }),
    // obsah soukromé komunikace
    prisma.privateMessage.deleteMany({
      where: { OR: [{ senderId: userId }, { recipientId: userId }] },
    }),
    prisma.errorLog.deleteMany({ where: { userId } }),
    prisma.syncMutation.deleteMany({ where: { userId } }),
    prisma.privacyNoticeAcceptance.deleteMany({ where: { userId } }),
    prisma.userMfaCredential.deleteMany({ where: { userId } }),
    prisma.mfaRecoveryCode.deleteMany({ where: { userId } }),
    prisma.authChallenge.deleteMany({ where: { userId } }),
    prisma.activityLog.updateMany({ where: { userId }, data: { metadata: Prisma.JsonNull } }),
    prisma.changeLog.updateMany({ where: { userId }, data: { metadata: Prisma.JsonNull } }),
    prisma.privacyErasure.create({
      data: {
        subjectUserId: userId,
        actorUserId: actorId,
        originalUsernameHash,
        details: {
          policyVersion: 1,
          retainedBusinessIdentity: 'anonymized-user-reference',
        },
      },
    }),
    prisma.user.update({
      where: { id: userId },
      data: {
        username: `${ANONYMIZED_USERNAME_PREFIX}${userId}`,
        displayName: 'Smazaný uživatel',
        pinHash: lockedPinHash,
        isActive: false,
        mustChangePin: false,
      },
    }),
  ]);
}
