import { createHash } from 'node:crypto';

import type { ProviderObservationV1, ProviderResultV1 } from '@/lib/providers';

export type CanonicalJson =
  | null
  | boolean
  | number
  | string
  | CanonicalJson[]
  | { [key: string]: CanonicalJson };

function canonicalValue(value: unknown): CanonicalJson {
  if (value === null) return null;
  if (typeof value === 'boolean' || typeof value === 'string') return value;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Valor numérico inválido.');
    return value;
  }
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return Object.fromEntries(
      Object.keys(record)
        .sort()
        .map((key) => [key, canonicalValue(record[key])])
    );
  }
  throw new Error('Valor não serializável no snapshot.');
}

export function canonicalizeSnapshot(value: unknown): string {
  return JSON.stringify(canonicalValue(value));
}

export function snapshotHash(value: unknown): string {
  return createHash('sha256')
    .update(canonicalizeSnapshot(value), 'utf8')
    .digest('hex');
}

export type SnapshotPayload = {
  readonly normalizedData: ProviderObservationV1['data'];
  readonly missingFields: readonly string[];
  readonly normalizerVersion: string;
  readonly evidenceRef?: string;
  readonly snapshotHash: string;
};

export function snapshotPayload(
  result: ProviderResultV1
): SnapshotPayload | null {
  if (result.kind !== 'observation' || result.status !== 'observed')
    return null;
  const normalizedData = result.data;
  return {
    normalizedData,
    missingFields: result.missingFields,
    normalizerVersion: result.provider.adapterVersion,
    ...(result.evidence?.evidenceRef
      ? { evidenceRef: result.evidence.evidenceRef }
      : {}),
    snapshotHash: snapshotHash(normalizedData),
  };
}
