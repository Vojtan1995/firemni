const SECRET_KEYS = new Set([
  'authorization',
  'cookie',
  'pin',
  'password',
  'credential',
  'code',
  'totp',
  'recoverycode',
  'recoverycodes',
  'challengetoken',
  'token',
  'jwt',
  'secret',
]);

export function redactText(value: string | undefined, maxLength = 20_000) {
  if (!value) return value;
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer [REDACTED]')
    .replace(
      /(["']?(?:pin|password|credential|code|token|secret|authorization)["']?\s*[:=]\s*)["']?[^"',\s}]+/gi,
      '$1[REDACTED]',
    )
    .slice(0, maxLength);
}

export function redactUnknown(value: unknown, depth = 0): unknown {
  if (depth > 8) return '[MAX_DEPTH]';
  if (typeof value === 'string') return redactText(value);
  if (Array.isArray(value)) return value.map((item) => redactUnknown(item, depth + 1));
  if (value && typeof value === 'object') {
    const output: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      output[key] = SECRET_KEYS.has(key.toLowerCase())
        ? '[REDACTED]'
        : redactUnknown(item, depth + 1);
    }
    return output;
  }
  return value;
}

export function sanitizeSentryEvent<T extends Record<string, any>>(event: T): T {
  const sanitized = redactUnknown(event) as T;
  if (sanitized.request) {
    delete sanitized.request.data;
    if (sanitized.request.headers) {
      delete sanitized.request.headers.Authorization;
      delete sanitized.request.headers.authorization;
      delete sanitized.request.headers.Cookie;
      delete sanitized.request.headers.cookie;
    }
  }
  delete sanitized.user;
  return sanitized;
}
