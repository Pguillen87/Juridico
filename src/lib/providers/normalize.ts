import { PROVIDER_CONTRACT_VERSION, type ProviderResultV1 } from './contract';

export function canonicalizeProviderInput(value: unknown): string {
  return JSON.stringify(sortValue(value));
}

function sortValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entry]) => [key, sortValue(entry)])
    );
  }
  return value;
}

export function assertProviderResult(
  result: ProviderResultV1
): ProviderResultV1 {
  if (result.contractVersion !== PROVIDER_CONTRACT_VERSION) {
    throw new Error('Contrato de provider incompatível.');
  }
  if (result.kind === 'observation' && result.status !== 'observed') {
    throw new Error('Observação de provider com status inválido.');
  }
  if (
    result.kind === 'failure' &&
    result.retryAfterMs !== undefined &&
    result.retryAfterMs < 0
  ) {
    throw new Error('Retry de provider inválido.');
  }
  return result;
}

export function providerFingerprint(input: unknown): string {
  const canonical = canonicalizeProviderInput(input);
  let hash = 0x811c9dc5;
  for (let index = 0; index < canonical.length; index += 1) {
    hash ^= canonical.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return `fnv1a-${(hash >>> 0).toString(16).padStart(8, '0')}`;
}
