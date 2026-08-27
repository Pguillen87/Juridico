import 'server-only';

import { createAdminClient } from '@/lib/supabase/admin';
import type { NormalizedProcessObservation } from '@/lib/providers/contract';
import {
  COMPARISON_VERSION_V1,
  type ComparisonSnapshot,
  compareSnapshots,
  type ComparisonOutput,
} from './comparator';

export type ComparisonRpcError = { readonly message: string };

export type ComparisonRpcClient = {
  rpc: (
    functionName: string,
    args: Record<string, unknown>
  ) => Promise<{ data: unknown; error: ComparisonRpcError | null }>;
};

export type PersistedComparison = ComparisonOutput & {
  readonly comparisonId: string;
  readonly detectedChangeId: string | null;
  readonly replayed: boolean;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Resposta comparativa inválida: ${name}.`);
  }
  return value;
}

function requiredJsonObject(
  value: unknown,
  name: string
): NormalizedProcessObservation {
  if (!isRecord(value))
    throw new Error(`Resposta comparativa inválida: ${name}.`);
  return value as unknown as NormalizedProcessObservation;
}

function requiredStringArray(value: unknown, name: string): readonly string[] {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
    throw new Error(`Resposta comparativa inválida: ${name}.`);
  }
  return value;
}

function snapshotFromRow(row: Record<string, unknown>): ComparisonSnapshot {
  return {
    id: requiredString(row.id, 'id'),
    officeId: requiredString(row.office_id, 'office_id'),
    processId: requiredString(row.process_id, 'process_id'),
    providerId: requiredString(row.provider_id, 'provider_id'),
    source: requiredString(row.source, 'source'),
    normalizerVersion: requiredString(
      row.normalizer_version,
      'normalizer_version'
    ),
    normalizedData: requiredJsonObject(row.normalized_data, 'normalized_data'),
    missingFields: requiredStringArray(row.missing_fields, 'missing_fields'),
    snapshotHash: requiredString(row.snapshot_hash, 'snapshot_hash'),
    createdAt: requiredString(row.created_at, 'created_at'),
  };
}

function snapshotPair(data: unknown): {
  readonly current: ComparisonSnapshot;
  readonly previous: ComparisonSnapshot | null;
} {
  if (!Array.isArray(data)) {
    throw new Error('Resposta do par de snapshots inválida.');
  }
  const rows = data.filter(isRecord);
  const currentRow = rows.find((row) => row.snapshot_role === 'current');
  if (!currentRow) throw new Error('Snapshot corrente não retornado.');
  const previousRow = rows.find((row) => row.snapshot_role === 'previous');
  return {
    current: snapshotFromRow(currentRow),
    previous: previousRow ? snapshotFromRow(previousRow) : null,
  };
}

function persistedRow(data: unknown): PersistedComparison {
  const row = Array.isArray(data) ? data[0] : data;
  if (!isRecord(row))
    throw new Error('Resposta da persistência comparativa inválida.');
  return {
    comparisonVersion: COMPARISON_VERSION_V1,
    comparisonId: requiredString(row.comparison_id, 'comparison_id'),
    detectedChangeId:
      typeof row.detected_change_id === 'string'
        ? row.detected_change_id
        : null,
    result: requiredString(row.result, 'result') as ComparisonOutput['result'],
    reasonCode:
      row.reason_code === null || row.reason_code === undefined
        ? null
        : (requiredString(
            row.reason_code,
            'reason_code'
          ) as ComparisonOutput['reasonCode']),
    changedFields: requiredStringArray(row.changed_fields, 'changed_fields'),
    normalizedDiff: isRecord(row.normalized_diff)
      ? (row.normalized_diff as ComparisonOutput['normalizedDiff'])
      : { entries: [] },
    comparisonHash: requiredString(row.comparison_hash, 'comparison_hash'),
    replayed: row.replayed === true,
  };
}

export async function compareAndPersistSnapshot(
  currentSnapshotId: string,
  client: ComparisonRpcClient = createAdminClient() as unknown as ComparisonRpcClient
): Promise<PersistedComparison> {
  const pairResponse = await client.rpc('phase10_get_snapshot_pair_internal', {
    p_current_snapshot_id: currentSnapshotId,
  });
  if (pairResponse.error) {
    throw new Error('Não foi possível carregar os snapshots para comparação.');
  }
  const pair = snapshotPair(pairResponse.data);
  const output = compareSnapshots(
    pair.previous,
    pair.current,
    COMPARISON_VERSION_V1
  );
  const persistResponse = await client.rpc('phase10_compare_process_snapshot', {
    p_current_snapshot_id: currentSnapshotId,
    p_comparison_version: output.comparisonVersion,
    p_result: output.result,
    p_reason_code: output.reasonCode,
    p_changed_fields: output.changedFields,
    p_normalized_diff: output.normalizedDiff,
  });
  if (persistResponse.error) {
    throw new Error('Não foi possível persistir o resultado comparativo.');
  }
  return persistedRow(persistResponse.data);
}
