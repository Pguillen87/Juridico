import { createHash } from 'node:crypto';
import { canonicalizeProviderInput } from './normalize';

export const PAYLOAD_SANITIZATION_VERSION = 'provider-payload-v1';
export const MAX_SANITIZED_PAYLOAD_BYTES = 256 * 1024;
export const MAX_SANITIZED_PAYLOAD_DEPTH = 20;
export const MAX_SANITIZED_ARRAY_ITEMS = 2_000;
export const MAX_SANITIZED_OBJECT_KEYS = 200;

const SENSITIVE_KEY =
  /^(authorization|api[_-]?key|token|access[_-]?token|refresh[_-]?token|cookie|set-cookie|password|secret|client[_-]?secret|service[_-]?role)$/i;
const SENSITIVE_VALUE =
  /(?:bearer\s+[a-z0-9._~+/=-]{8,}|apikey\s*[=:]\s*\S{8,}|(?:https?|postgres(?:ql)?)\:\/\/[^/\s:@]+\:[^/\s@]+@)/i;

export class PayloadSanitizationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PayloadSanitizationError';
  }
}

function isJsonPrimitive(
  value: unknown
): value is string | number | boolean | null {
  return (
    value === null ||
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  );
}

function sanitizeValue(value: unknown, depth: number): unknown {
  if (depth > MAX_SANITIZED_PAYLOAD_DEPTH) {
    throw new PayloadSanitizationError('payload depth exceeded');
  }
  if (isJsonPrimitive(value)) {
    if (typeof value === 'string') {
      if (value.length > 20_000) {
        throw new PayloadSanitizationError('payload string exceeded');
      }
      if (SENSITIVE_VALUE.test(value)) {
        throw new PayloadSanitizationError(
          'payload contains a sensitive value'
        );
      }
    }
    if (typeof value === 'number' && !Number.isFinite(value)) {
      throw new PayloadSanitizationError('payload contains an invalid number');
    }
    return value;
  }
  if (Array.isArray(value)) {
    if (value.length > MAX_SANITIZED_ARRAY_ITEMS) {
      throw new PayloadSanitizationError('payload array exceeded');
    }
    return value.map((entry) => sanitizeValue(entry, depth + 1));
  }
  if (!value || typeof value !== 'object') {
    throw new PayloadSanitizationError('payload contains a non-JSON value');
  }

  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > MAX_SANITIZED_OBJECT_KEYS) {
    throw new PayloadSanitizationError('payload object exceeded');
  }
  const output: Record<string, unknown> = {};
  for (const [key, entry] of entries.sort(([left], [right]) =>
    left.localeCompare(right)
  )) {
    if (key.length === 0 || key.length > 120) {
      throw new PayloadSanitizationError('payload key is invalid');
    }
    if (SENSITIVE_KEY.test(key)) continue;
    output[key] = sanitizeValue(entry, depth + 1);
  }
  return output;
}

export function sanitizeRawProviderPayload(value: unknown): {
  readonly payload: unknown;
  readonly canonicalJson: string;
  readonly payloadHash: string;
  readonly payloadBytes: number;
} {
  if (!Array.isArray(value) && (!value || typeof value !== 'object')) {
    throw new PayloadSanitizationError(
      'payload root must be an object or array'
    );
  }
  const payload = sanitizeValue(value, 0);
  const canonicalJson = canonicalizeProviderInput(payload);
  if (
    /(?:^|["'])changed(?:["']|$)|(?:^|["'])unchanged(?:["']|$)/.test(
      canonicalJson
    )
  ) {
    throw new PayloadSanitizationError(
      'comparison states are not allowed in provider payload'
    );
  }
  const payloadBytes = Buffer.byteLength(canonicalJson, 'utf8');
  if (payloadBytes < 1 || payloadBytes > MAX_SANITIZED_PAYLOAD_BYTES) {
    throw new PayloadSanitizationError(
      'payload size is outside the allowed range'
    );
  }
  const payloadHash = createHash('sha256')
    .update(canonicalJson, 'utf8')
    .digest('hex');
  return { payload, canonicalJson, payloadHash, payloadBytes };
}
