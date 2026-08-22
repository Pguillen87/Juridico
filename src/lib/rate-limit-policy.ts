export const rateLimitPolicies = {
  'admin.invite': { limit: 5, windowSeconds: 15 * 60 },
  'admin.change_role': { limit: 20, windowSeconds: 15 * 60 },
  'admin.set_active': { limit: 20, windowSeconds: 15 * 60 },
  'admin.set_owner': { limit: 10, windowSeconds: 15 * 60 },
  'admin.update_office_name': { limit: 10, windowSeconds: 15 * 60 },
  'admin.audit_export': { limit: 3, windowSeconds: 60 * 60 },
} as const;

export type AdminRateLimitOperation = keyof typeof rateLimitPolicies;

export type RateLimitResult = {
  allowed: boolean;
  retryAfterSeconds: number;
  currentCount: number;
  limitCount: number;
  windowSeconds: number;
};

export function isRateLimitAllowed(result: RateLimitResult): boolean {
  return result.allowed && result.currentCount <= result.limitCount;
}
