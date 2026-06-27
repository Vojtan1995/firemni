import { describe, expect, it } from '@jest/globals';
import {
  redactText,
  redactUnknown,
  sanitizeSentryEvent,
} from '../dist/lib/redaction.js';

describe('secret and PII redaction', () => {
  it('redacts bearer tokens and authentication fields from text', () => {
    const source =
      'Authorization: Bearer abc.def.ghi password=TopSecret123 token=opaque-token';
    const redacted = redactText(source);
    expect(redacted).not.toContain('abc.def.ghi');
    expect(redacted).not.toContain('TopSecret123');
    expect(redacted).not.toContain('opaque-token');
  });

  it('redacts nested MFA, recovery and credential fields', () => {
    const redacted = redactUnknown({
      body: {
        credential: 'AdminPassword',
        code: '123456',
        recoveryCodes: ['secret-code'],
      },
      safe: 'visible',
    });
    expect(redacted).toEqual({
      body: {
        credential: '[REDACTED]',
        code: '[REDACTED]',
        recoveryCodes: '[REDACTED]',
      },
      safe: 'visible',
    });
  });

  it('drops Sentry request bodies, auth headers and user identity', () => {
    const event = sanitizeSentryEvent({
      request: {
        data: { pin: '654321' },
        headers: { Authorization: 'Bearer token', Cookie: 'sid=secret', Accept: 'json' },
      },
      user: { id: 'personal-id', email: 'person@example.test' },
      tags: { component: 'api' },
    });
    expect(event.request.data).toBeUndefined();
    expect(event.request.headers.Authorization).toBeUndefined();
    expect(event.request.headers.Cookie).toBeUndefined();
    expect(event.user).toBeUndefined();
    expect(event.tags.component).toBe('api');
  });
});
