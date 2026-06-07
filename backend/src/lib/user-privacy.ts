import { UserRole } from '@prisma/client';

export const ADMIN_ANONYMOUS_LABEL = 'Administrátor';
export const ADMIN_ANONYMOUS_USERNAME = 'admin';

export function shouldAnonymizeAdmin(viewerRole: UserRole): boolean {
  return viewerRole !== UserRole.admin;
}

type UserLike = {
  id: string;
  displayName: string;
  username?: string;
  role?: UserRole;
};

export function anonymizeUserForViewer<T extends UserLike>(
  user: T,
  viewerRole: UserRole,
): T {
  if (!shouldAnonymizeAdmin(viewerRole) || user.role !== UserRole.admin) {
    return user;
  }
  return {
    ...user,
    displayName: ADMIN_ANONYMOUS_LABEL,
    username: ADMIN_ANONYMOUS_USERNAME,
  };
}

export function anonymizeOptionalUserForViewer<T extends UserLike>(
  user: T | null | undefined,
  viewerRole: UserRole,
): T | null | undefined {
  if (!user) return user;
  return anonymizeUserForViewer(user, viewerRole);
}

export function mapLogUsers<T extends { user?: UserLike | null }>(
  rows: T[],
  viewerRole: UserRole,
): T[] {
  return rows.map((row) => {
    if (!row.user) return row;
    return { ...row, user: anonymizeUserForViewer(row.user, viewerRole) };
  });
}

export function mapMessageUsers<
  T extends {
    sender: UserLike;
    recipient: UserLike;
  },
>(messages: T[], viewerRole: UserRole): T[] {
  return messages.map((message) => ({
    ...message,
    sender: anonymizeUserForViewer(message.sender, viewerRole),
    recipient: anonymizeUserForViewer(message.recipient, viewerRole),
  }));
}
