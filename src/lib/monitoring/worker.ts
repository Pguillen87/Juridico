import 'server-only';

import { randomUUID } from 'node:crypto';

import { createAdminClient } from '@/lib/supabase/admin';
import {
  createDataJudProvider,
  type DataJudProviderInput,
} from '@/lib/providers/adapters/datajud-server';
import {
  PROVIDER_CONTRACT_VERSION,
  type ProviderFailureV1,
  type ProviderRequestV1,
  type ProviderResultV1,
} from '@/lib/providers/contract';
import { failurePolicy, sanitizeProviderMessage } from '@/lib/providers/errors';
import { createDefaultProviderGateway } from '@/lib/providers/registry-server';
import {
  PAYLOAD_SANITIZATION_VERSION,
  sanitizeRawProviderPayload,
} from '@/lib/providers/payload';
import type { ProviderExecutionWithPayload } from '@/lib/providers/registry';
import {
  compareAndPersistSnapshot,
  type PersistedComparison,
} from '@/lib/comparison/persistence';
import {
  emitDetectedChange,
  reconcileExecutionFailure,
  reconcileSuccessfulExecution,
  recordComparisonPersistenceFailure,
  recordInternalFailure,
} from '@/lib/failures/server';

export const PHASE9_LEASE_DURATION_MS = 30_000;

export type MonitoringRpcError = { readonly message: string };

export type MonitoringRpcClient = {
  rpc: (
    functionName: string,
    args: Record<string, unknown>
  ) => Promise<{ data: unknown; error: MonitoringRpcError | null }>;
};

type QueryJobClaim = {
  readonly job_id: string;
  readonly execution_id: string;
  readonly office_id: string;
  readonly process_id: string;
  readonly provider_id: 'datajud_sandbox';
  readonly capability: 'process_observation';
  readonly job_kind: 'scheduled' | 'manual_reprocess';
  readonly subject_ref: string;
  readonly request_fingerprint: string;
  readonly correlation_id: string;
  readonly attempt_number: number;
  readonly lease_token: string;
  readonly lease_expires_at: string;
};

type QueryExecutionCompletion = {
  readonly job_id: string;
  readonly execution_id: string;
  readonly job_status:
    'succeeded' | 'retry_scheduled' | 'terminal_failure' | 'cancelled';
  readonly exchange_id: string;
  readonly snapshot_id: string | null;
  readonly next_attempt_at: string | null;
};

export type WorkerComparisonResult =
  | { readonly status: 'completed'; readonly value: PersistedComparison }
  | {
      readonly status: 'failed';
      readonly errorCode: 'comparison_persistence_failed';
    };

export type WorkerRunResult =
  | { readonly status: 'idle'; readonly workerId: string }
  | {
      readonly status: 'completed';
      readonly workerId: string;
      readonly claim: QueryJobClaim;
      readonly completion: QueryExecutionCompletion;
      readonly result: ProviderResultV1;
      readonly comparison: WorkerComparisonResult | null;
    }
  | {
      readonly status: 'stale_or_rejected';
      readonly workerId: string;
      readonly claim: QueryJobClaim;
      readonly result: ProviderResultV1;
    };

type WorkerOptions = {
  readonly client?: MonitoringRpcClient;
  readonly providerInput?: DataJudProviderInput;
  readonly workerId?: string;
  readonly leaseDurationMs?: number;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function claimFrom(value: unknown): QueryJobClaim | null {
  const row = Array.isArray(value) ? value[0] : value;
  if (!isRecord(row)) return null;
  const requiredStrings = [
    'job_id',
    'execution_id',
    'office_id',
    'process_id',
    'provider_id',
    'capability',
    'job_kind',
    'subject_ref',
    'request_fingerprint',
    'correlation_id',
    'lease_token',
    'lease_expires_at',
  ];
  if (
    requiredStrings.some(
      (key) => typeof row[key] !== 'string' || row[key] === ''
    ) ||
    row.provider_id !== 'datajud_sandbox' ||
    row.capability !== 'process_observation' ||
    (row.job_kind !== 'scheduled' && row.job_kind !== 'manual_reprocess') ||
    typeof row.attempt_number !== 'number' ||
    !Number.isInteger(row.attempt_number) ||
    row.attempt_number < 1 ||
    row.attempt_number > 3
  ) {
    return null;
  }
  return row as unknown as QueryJobClaim;
}

function completionFrom(value: unknown): QueryExecutionCompletion | null {
  const row = Array.isArray(value) ? value[0] : value;
  if (!isRecord(row)) return null;
  if (
    typeof row.job_id !== 'string' ||
    typeof row.execution_id !== 'string' ||
    typeof row.job_status !== 'string' ||
    !['succeeded', 'retry_scheduled', 'terminal_failure', 'cancelled'].includes(
      row.job_status
    ) ||
    typeof row.exchange_id !== 'string'
  ) {
    return null;
  }
  return {
    job_id: row.job_id,
    execution_id: row.execution_id,
    job_status: row.job_status as QueryExecutionCompletion['job_status'],
    exchange_id: row.exchange_id,
    snapshot_id: typeof row.snapshot_id === 'string' ? row.snapshot_id : null,
    next_attempt_at:
      typeof row.next_attempt_at === 'string' ? row.next_attempt_at : null,
  };
}

function sanitizationFailure(result: ProviderResultV1): ProviderFailureV1 {
  return {
    kind: 'failure',
    status: 'technical_failure',
    provider: result.provider,
    source: result.source,
    contractVersion: PROVIDER_CONTRACT_VERSION,
    capability: result.capability,
    errorCode: 'datajud_payload_sanitization_failed',
    message: sanitizeProviderMessage('technical_failure'),
    ...failurePolicy('technical_failure'),
    sourceMetadata: result.sourceMetadata,
    correlationId: result.correlationId,
  };
}

function buildRequest(
  claim: QueryJobClaim,
  workerId: string
): ProviderRequestV1 {
  return {
    contractVersion: PROVIDER_CONTRACT_VERSION,
    operation: 'observe_process',
    capability: claim.capability,
    subjectRef: { type: 'process', value: claim.subject_ref },
    requestFingerprint: claim.request_fingerprint,
    correlationId: claim.correlation_id,
    requestedAt: new Date().toISOString(),
    executionContext: {
      kind: 'system',
      actorUserId: null,
      officeId: claim.office_id,
      role: null,
      isOwner: false,
      workerId,
    },
  };
}

async function executeProvider(
  claim: QueryJobClaim,
  workerId: string,
  providerInput: DataJudProviderInput | undefined
): Promise<ProviderExecutionWithPayload> {
  const gateway = createDefaultProviderGateway();
  const request = buildRequest(claim, workerId);
  return gateway.observeWithPayload(claim.provider_id, request, providerInput);
}

export async function runMonitoringWorkerOnce(
  options: WorkerOptions = {}
): Promise<WorkerRunResult> {
  const workerId = options.workerId ?? `worker-${randomUUID()}`;
  const leaseDurationMs = options.leaseDurationMs ?? PHASE9_LEASE_DURATION_MS;
  const client =
    options.client ?? (createAdminClient() as unknown as MonitoringRpcClient);
  const claimResponse = await client.rpc('phase9_claim_query_job', {
    p_worker_id: workerId,
    p_lease_duration_ms: leaseDurationMs,
  });
  if (claimResponse.error)
    throw new Error('Não foi possível reivindicar o job.');
  const claim = claimFrom(claimResponse.data);
  if (!claim) return { status: 'idle', workerId };

  let execution: ProviderExecutionWithPayload;
  try {
    execution = await executeProvider(
      claim,
      workerId,
      options.providerInput ?? { scenario: 'success' }
    );
  } catch {
    execution = {
      result: {
        kind: 'failure',
        status: 'technical_failure',
        provider: createDataJudProvider().descriptor,
        source: 'datajud',
        contractVersion: PROVIDER_CONTRACT_VERSION,
        capability: claim.capability,
        errorCode: 'worker_provider_execution_failed',
        message: sanitizeProviderMessage('technical_failure'),
        ...failurePolicy('technical_failure'),
        sourceMetadata: {
          sourceType: 'datajud',
          providerId: claim.provider_id,
          adapterVersion: createDataJudProvider().descriptor.adapterVersion,
          contractVersion: PROVIDER_CONTRACT_VERSION,
          observedAt: new Date().toISOString(),
          durationMs: 0,
        },
        correlationId: claim.correlation_id,
      },
    };
  }

  let result = execution.result;
  let sanitizedPayload: ReturnType<typeof sanitizeRawProviderPayload> | null =
    null;
  if (execution.rawPayload !== undefined) {
    try {
      sanitizedPayload = sanitizeRawProviderPayload(execution.rawPayload);
    } catch {
      result = sanitizationFailure(result);
    }
  }

  const completionResponse = await client.rpc(
    'phase9_complete_query_execution',
    {
      p_job_id: claim.job_id,
      p_execution_id: claim.execution_id,
      p_lease_token: claim.lease_token,
      p_result_kind: result.kind,
      p_result_status: result.status,
      p_error_code: result.kind === 'failure' ? result.errorCode : null,
      p_normalized_result: result.kind === 'observation' ? result : null,
      p_raw_payload: sanitizedPayload?.payload ?? null,
      p_sanitization_version: sanitizedPayload
        ? PAYLOAD_SANITIZATION_VERSION
        : null,
      p_received_at: result.sourceMetadata.observedAt,
      p_http_status: null,
      p_duration_ms: result.sourceMetadata.durationMs ?? 0,
      p_retry_after_ms:
        result.kind === 'failure' ? (result.retryAfterMs ?? null) : null,
    }
  );
  if (completionResponse.error) {
    await recordInternalFailure(
      {
        officeId: claim.office_id,
        processId: claim.process_id,
        origin: 'persistence',
        failureStage: 'persistence',
        failureClass: 'persistence',
        failureCode: 'provider_persistence_failed',
        sourceType: 'query_execution',
        sourceId: claim.execution_id,
      },
      client
    );
    return { status: 'stale_or_rejected', workerId, claim, result };
  }
  const completion = completionFrom(completionResponse.data);
  if (!completion) {
    await recordInternalFailure(
      {
        officeId: claim.office_id,
        processId: claim.process_id,
        origin: 'persistence',
        failureStage: 'persistence',
        failureClass: 'persistence',
        failureCode: 'provider_persistence_failed',
        sourceType: 'query_execution',
        sourceId: claim.execution_id,
      },
      client
    );
    return { status: 'stale_or_rejected', workerId, claim, result };
  }

  if (result.kind === 'failure') {
    await reconcileExecutionFailure(claim.execution_id, client);
  }

  let comparison: WorkerComparisonResult | null = null;
  if (completion.snapshot_id) {
    try {
      const persistedComparison = await compareAndPersistSnapshot(
        completion.snapshot_id,
        client
      );
      comparison = {
        status: 'completed',
        value: persistedComparison,
      };
      if (persistedComparison.detectedChangeId) {
        const emitted = await emitDetectedChange(
          persistedComparison.detectedChangeId,
          client
        );
        if (!emitted) {
          await recordInternalFailure(
            {
              officeId: claim.office_id,
              processId: claim.process_id,
              origin: 'notification',
              failureStage: 'notification',
              failureClass: 'notification',
              failureCode: 'outbox_persistence_failed',
              sourceType: 'detected_change',
              sourceId: persistedComparison.detectedChangeId,
            },
            client
          );
        }
      }
    } catch {
      comparison = {
        status: 'failed',
        errorCode: 'comparison_persistence_failed',
      };
      await recordComparisonPersistenceFailure(
        {
          officeId: claim.office_id,
          processId: claim.process_id,
          providerId: claim.provider_id,
          capability: claim.capability,
          snapshotId: completion.snapshot_id,
        },
        client
      );
    }
  }

  if (completion.job_status === 'succeeded') {
    await reconcileSuccessfulExecution(claim.execution_id, client);
  }
  return {
    status: 'completed',
    workerId,
    claim,
    completion,
    result,
    comparison,
  };
}
