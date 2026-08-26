import type { ProviderFailureV1, ProviderResultV1 } from '@/lib/providers';

export const MAX_JOB_ATTEMPTS = 3;
export const RETRY_AFTER_CEILING_MS = 60_000;
export const DEFAULT_BACKOFF_BASE_MS = 1_000;

const RETRYABLE_FAILURES = new Set<ProviderFailureV1['status']>([
  'rate_limited',
  'timeout',
  'source_unavailable',
]);

export function boundedRetryAfterMs(value: number | undefined): number {
  if (value === undefined || !Number.isFinite(value) || value < 0) return 0;
  return Math.min(Math.floor(value), RETRY_AFTER_CEILING_MS);
}

export function shouldRetry(
  result: ProviderResultV1,
  attemptNumber: number,
  maxAttempts = MAX_JOB_ATTEMPTS
): boolean {
  return (
    result.kind === 'failure' &&
    RETRYABLE_FAILURES.has(result.status) &&
    attemptNumber < maxAttempts
  );
}

export function retryDelayMs(
  result: ProviderResultV1,
  attemptNumber: number
): number | null {
  if (result.kind !== 'failure' || !shouldRetry(result, attemptNumber)) {
    return null;
  }
  const exponential =
    DEFAULT_BACKOFF_BASE_MS * 2 ** Math.max(attemptNumber - 1, 0);
  return Math.min(
    RETRY_AFTER_CEILING_MS,
    Math.max(exponential, boundedRetryAfterMs(result.retryAfterMs))
  );
}

export function nextRetryAt(
  result: ProviderResultV1,
  attemptNumber: number,
  now = new Date()
): Date | null {
  const delay = retryDelayMs(result, attemptNumber);
  if (delay === null) return null;
  return new Date(now.getTime() + delay);
}

export function terminalFailureStatus(
  result: ProviderResultV1,
  attemptNumber: number,
  maxAttempts = MAX_JOB_ATTEMPTS
): 'retry_scheduled' | 'terminal_failure' | 'succeeded' {
  if (result.kind === 'observation') return 'succeeded';
  return shouldRetry(result, attemptNumber, maxAttempts)
    ? 'retry_scheduled'
    : 'terminal_failure';
}
