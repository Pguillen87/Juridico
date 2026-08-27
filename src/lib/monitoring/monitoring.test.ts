import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));

import type { ProviderResultV1 } from '@/lib/providers';
import {
  boundedRetryAfterMs,
  nextRetryAt,
  retryDelayMs,
  shouldRetry,
} from './retry';
import {
  canonicalizeSnapshot,
  snapshotHash,
  snapshotPayload,
} from './snapshots';
import { runMonitoringSchedulerTick } from './scheduler';
import { runMonitoringWorkerOnce, type MonitoringRpcClient } from './worker';

const observation: ProviderResultV1 = {
  kind: 'observation',
  status: 'observed',
  provider: {
    providerId: 'datajud_sandbox',
    providerKind: 'datajud',
    adapterVersion: '1.0.0',
    contractVersion: 1,
  },
  source: 'datajud',
  contractVersion: 1,
  capability: 'process_observation',
  data: {
    processRef: '91000000000000000011',
    tribunal: 'TJ-SYNTHETIC',
  },
  returnedFields: ['processRef', 'tribunal'],
  missingFields: ['system', 'movements', 'parties'],
  sourceMetadata: {
    sourceType: 'datajud',
    providerId: 'datajud_sandbox',
    adapterVersion: '1.0.0',
    contractVersion: 1,
    observedAt: '2026-01-01T11:00:00.000Z',
    durationMs: 12,
  },
  correlationId: 'phase9-correlation-001',
};

function failure(
  status: 'timeout' | 'rate_limited' | 'source_unavailable'
): ProviderResultV1 {
  return {
    kind: 'failure',
    status,
    provider: observation.provider,
    source: 'datajud',
    contractVersion: 1,
    capability: 'process_observation',
    errorCode: `datajud_${status}`,
    message: 'Falha sintética.',
    retryable: true,
    retryAfterMs: status === 'rate_limited' ? 5000 : undefined,
    sourceMetadata: observation.sourceMetadata,
    correlationId: observation.correlationId,
  };
}

describe('Fase 9 — retry e snapshot', () => {
  it('canonicaliza chaves sem misturar ordem semântica de arrays', () => {
    expect(canonicalizeSnapshot({ b: 2, a: 1 })).toBe(
      canonicalizeSnapshot({ a: 1, b: 2 })
    );
    expect(snapshotHash({ b: 2, a: 1 })).toBe(snapshotHash({ a: 1, b: 2 }));
    expect(snapshotHash({ items: [1, 2] })).not.toBe(
      snapshotHash({ items: [2, 1] })
    );
  });

  it('produz snapshot apenas para observation válida', () => {
    const payload = snapshotPayload(observation);
    expect(payload).toMatchObject({
      normalizerVersion: '1.0.0',
      missingFields: ['system', 'movements', 'parties'],
    });
    expect(payload?.snapshotHash).toMatch(/^[0-9a-f]{64}$/);
    expect(snapshotPayload(failure('timeout'))).toBeNull();
  });

  it('aplica backoff determinístico, teto e máximo de três tentativas', () => {
    expect(boundedRetryAfterMs(999_999)).toBe(60_000);
    expect(retryDelayMs(failure('timeout'), 1)).toBe(1_000);
    expect(retryDelayMs(failure('rate_limited'), 2)).toBe(5_000);
    expect(shouldRetry(failure('source_unavailable'), 2, 3)).toBe(true);
    expect(shouldRetry(failure('timeout'), 3, 3)).toBe(false);
    expect(nextRetryAt(failure('timeout'), 1, new Date(0))?.getTime()).toBe(
      1_000
    );
  });
});

describe('Fase 9 — scheduler e worker backend-only', () => {
  beforeEach(() => vi.restoreAllMocks());

  it('chama somente o tick interno com instante controlado', async () => {
    const rpc = vi.fn(async () => ({ data: 2, error: null }));
    const result = await runMonitoringSchedulerTick(new Date(0), {
      toleranceSeconds: 120,
      client: { rpc },
    });

    expect(result).toEqual({
      scheduledAt: '1970-01-01T00:00:00.000Z',
      createdJobs: 2,
    });
    expect(rpc).toHaveBeenCalledWith('phase9_scheduler_tick', {
      p_as_of: '1970-01-01T00:00:00.000Z',
      p_window_tolerance_seconds: 120,
    });
  });

  it('reivindica e conclui via RPCs internas, sem actor jurídico', async () => {
    const rpc = vi
      .fn<MonitoringRpcClient['rpc']>()
      .mockResolvedValueOnce({
        data: [
          {
            job_id: '91000000-0000-4000-d000-000000000001',
            execution_id: '91000000-0000-4000-e000-000000000001',
            office_id: '91000000-0000-4000-9000-000000000001',
            process_id: '91000000-0000-4000-c000-000000000001',
            provider_id: 'datajud_sandbox',
            capability: 'process_observation',
            job_kind: 'scheduled',
            subject_ref: '91000000000000000011',
            request_fingerprint: 'a'.repeat(64),
            correlation_id: 'phase9-execution-001',
            attempt_number: 1,
            lease_token: '91000000-0000-4000-f000-000000000001',
            lease_expires_at: '2026-01-01T11:00:30.000Z',
          },
        ],
        error: null,
      })
      .mockResolvedValueOnce({
        data: [
          {
            job_id: '91000000-0000-4000-d000-000000000001',
            execution_id: '91000000-0000-4000-e000-000000000001',
            job_status: 'succeeded',
            exchange_id: '91000000-0000-4000-a000-000000000001',
            snapshot_id: '91000000-0000-4000-b000-000000000001',
            next_attempt_at: null,
          },
        ],
        error: null,
      })
      .mockResolvedValueOnce({
        data: [
          {
            snapshot_role: 'current',
            id: '91000000-0000-4000-b000-000000000001',
            office_id: '91000000-0000-4000-9000-000000000001',
            process_id: '91000000-0000-4000-c000-000000000001',
            provider_id: 'datajud_sandbox',
            source: 'datajud',
            normalizer_version: '1.0.0',
            normalized_data: observation.data,
            missing_fields: observation.missingFields,
            snapshot_hash: snapshotHash(observation.data),
            created_at: '2026-01-01T11:00:00.000Z',
          },
        ],
        error: null,
      })
      .mockResolvedValueOnce({
        data: [
          {
            comparison_id: '91000000-0000-4000-1100-000000000001',
            detected_change_id: null,
            result: 'not_comparable',
            reason_code: 'first_snapshot',
            changed_fields: [],
            normalized_diff: { entries: [] },
            comparison_hash: 'b'.repeat(64),
            replayed: false,
          },
        ],
        error: null,
      });
    const client: MonitoringRpcClient = { rpc };

    const result = await runMonitoringWorkerOnce({
      client,
      workerId: 'phase9-worker-test',
      providerInput: { scenario: 'success' },
    });

    expect(result.status).toBe('completed');
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'phase9_claim_query_job',
      'phase9_complete_query_execution',
      'phase10_get_snapshot_pair_compatible_internal',
      'phase10_compare_process_snapshot_v2',
    ]);
    expect(rpc).toHaveBeenNthCalledWith(1, 'phase9_claim_query_job', {
      p_worker_id: 'phase9-worker-test',
      p_lease_duration_ms: 30_000,
    });
    expect(rpc).toHaveBeenNthCalledWith(
      2,
      'phase9_complete_query_execution',
      expect.objectContaining({
        p_job_id: '91000000-0000-4000-d000-000000000001',
        p_execution_id: '91000000-0000-4000-e000-000000000001',
        p_result_kind: 'observation',
        p_result_status: 'observed',
        p_raw_payload: expect.objectContaining({
          processRef: '91000000000000000011',
        }),
      })
    );
    expect(JSON.stringify(rpc.mock.calls)).not.toContain('service_role');
    expect(rpc.mock.calls[1]?.[1]).not.toMatchObject({
      p_result: 'changed',
      p_result_status: 'changed',
    });
    expect(result.status === 'completed' && result.comparison).toMatchObject({
      status: 'completed',
      value: { result: 'not_comparable', reasonCode: 'first_snapshot' },
    });
  });
});
