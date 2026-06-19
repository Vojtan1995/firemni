import bcrypt from 'bcrypt';
import { User, UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';
import { VEDENI_ROLES } from '../lib/permissions.js';

export const MANAGEMENT_ROLES = VEDENI_ROLES;

const ASSIGNABLE_BY_VEDENI: UserRole[] = [UserRole.worker, UserRole.vedeni];

export type PublicUser = {
  id: string;
  username: string;
  displayName: string;
  role: UserRole;
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
  data: { username: string; displayName: string; pin: string; role: UserRole },
): Promise<PublicUser> {
  assertRoleAssignable(actorRole, data.role);

  const existing = await prisma.user.findUnique({ where: { username: data.username } });
  if (existing) throw badRequest('Uživatelské jméno již existuje');

  const pinHash = await bcrypt.hash(data.pin, 10);
  const user = await prisma.user.create({
    data: {
      username: data.username,
      displayName: data.displayName,
      pinHash,
      role: data.role,
      mustChangePin: true,
    },
  });
  return toPublicUser(user);
}

export async function updateUser(
  actorRole: UserRole,
  actorId: string,
  userId: string,
  data: Partial<{ displayName: string; pin: string; role: UserRole; isActive: boolean }>,
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
  } = {};

  if (data.displayName !== undefined) updateData.displayName = data.displayName;
  if (data.role !== undefined) updateData.role = data.role;
  if (data.isActive !== undefined) updateData.isActive = data.isActive;
  if (data.pin !== undefined) {
    updateData.pinHash = await bcrypt.hash(data.pin, 10);
    updateData.mustChangePin = true;
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
