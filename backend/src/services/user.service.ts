import bcrypt from 'bcrypt';
import { User, UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { badRequest, forbidden, notFound } from '../lib/errors.js';

export const MANAGEMENT_ROLES: UserRole[] = [UserRole.management, UserRole.admin];

const ASSIGNABLE_BY_MANAGEMENT: UserRole[] = [UserRole.worker, UserRole.management];

export type PublicUser = {
  id: string;
  username: string;
  displayName: string;
  role: UserRole;
  isActive: boolean;
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
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  };
}

function assertRoleAssignable(actorRole: UserRole, role: UserRole) {
  if (actorRole === UserRole.admin) return;
  if (role === UserRole.admin || !ASSIGNABLE_BY_MANAGEMENT.includes(role)) {
    throw forbidden('Vedení nemůže spravovat účty s rolí admin');
  }
}

function assertCanManageTarget(actorRole: UserRole, target: User) {
  if (actorRole === UserRole.admin) return;
  if (target.role === UserRole.admin) {
    throw forbidden('Vedení nemůže upravovat administrátorské účty');
  }
}

export async function listUsers(): Promise<PublicUser[]> {
  const users = await prisma.user.findMany({ orderBy: { username: 'asc' } });
  return users.map(toPublicUser);
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
  } = {};

  if (data.displayName !== undefined) updateData.displayName = data.displayName;
  if (data.role !== undefined) updateData.role = data.role;
  if (data.isActive !== undefined) updateData.isActive = data.isActive;
  if (data.pin !== undefined) {
    updateData.pinHash = await bcrypt.hash(data.pin, 10);
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
