import { describe, expect, it } from 'vitest';
import {
  isRateLimitAllowed,
  rateLimitPolicies,
  type RateLimitResult,
} from './rate-limit-policy';

describe('política de rate limit administrativo', () => {
  it('mantém os seis defaults aprovados', () => {
    expect(rateLimitPolicies).toEqual({
      'admin.invite': { limit: 5, windowSeconds: 900 },
      'admin.change_role': { limit: 20, windowSeconds: 900 },
      'admin.set_active': { limit: 20, windowSeconds: 900 },
      'admin.set_owner': { limit: 10, windowSeconds: 900 },
      'admin.update_office_name': { limit: 10, windowSeconds: 900 },
      'admin.audit_export': { limit: 3, windowSeconds: 3600 },
    });
  });

  it('permite contagem dentro do limite e bloqueia a excedente', () => {
    const allowed: RateLimitResult = {
      allowed: true,
      retryAfterSeconds: 0,
      currentCount: 5,
      limitCount: 5,
      windowSeconds: 900,
    };
    const blocked: RateLimitResult = {
      ...allowed,
      allowed: false,
      currentCount: 6,
      retryAfterSeconds: 421,
    };

    expect(isRateLimitAllowed(allowed)).toBe(true);
    expect(isRateLimitAllowed(blocked)).toBe(false);
  });

  it('não trata contagem acima do limite como permitida mesmo se o backend marcar allowed', () => {
    expect(
      isRateLimitAllowed({
        allowed: true,
        retryAfterSeconds: 0,
        currentCount: 21,
        limitCount: 20,
        windowSeconds: 900,
      })
    ).toBe(false);
  });
});
