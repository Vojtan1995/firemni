import { createHash } from 'crypto';

/** SHA-256 hash of JWT — stored in DB instead of the raw token. */
export function hashSessionToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
