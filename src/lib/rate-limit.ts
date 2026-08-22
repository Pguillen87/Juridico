import 'server-only';

import { createClient } from './supabase/server';
import {
  type AdminRateLimitOperation,
  type RateLimitResult,
  isRateLimitAllowed,
  rateLimitPolicies,
} from './rate-limit-policy';

export {
  isRateLimitAllowed,
  rateLimitPolicies,
  type AdminRateLimitOperation,
  type RateLimitResult,
};

export async function consumeAdminRateLimit(
  operation: AdminRateLimitOperation
): Promise<RateLimitResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('consume_admin_rate_limit', {
    p_operation: operation,
  });
  const result = data?.[0];

  if (error || !result) {
    throw new Error('Não foi possível validar o limite temporário.');
  }

  return {
    allowed: result.allowed,
    retryAfterSeconds: result.retry_after_seconds,
    currentCount: result.current_count,
    limitCount: result.limit_count,
    windowSeconds: result.window_seconds,
  };
}
