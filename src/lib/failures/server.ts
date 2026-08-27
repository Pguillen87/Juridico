import 'server-only';

import { createAdminClient } from '@/lib/supabase/admin';
import type { MonitoringRpcClient } from '@/lib/monitoring/worker';

export type FailureRpcClient = MonitoringRpcClient;

export async function reconcileExecutionFailure(
  executionId: string,
  client: FailureRpcClient = createAdminClient() as unknown as FailureRpcClient
): Promise<string | null> {
  const { data, error } = await client.rpc(
    'phase11_record_execution_failure_internal',
    { p_execution_id: executionId }
  );
  if (error) return null;
  const row = Array.isArray(data) ? data[0] : data;
  return typeof row === 'string' ? row : null;
}

export async function reconcileSuccessfulExecution(
  executionId: string,
  client: FailureRpcClient = createAdminClient() as unknown as FailureRpcClient
): Promise<number> {
  const { data, error } = await client.rpc(
    'phase11_reconcile_success_internal',
    { p_execution_id: executionId }
  );
  if (error) return 0;
  const row = Array.isArray(data) ? data[0] : data;
  return typeof row === 'number' && Number.isInteger(row) ? row : 0;
}

export async function emitDetectedChange(
  detectedChangeId: string,
  client: FailureRpcClient = createAdminClient() as unknown as FailureRpcClient
): Promise<boolean> {
  const { data, error } = await client.rpc(
    'phase11_emit_detected_change_internal',
    { p_detected_change_id: detectedChangeId }
  );
  if (error) return false;
  const row = Array.isArray(data) ? data[0] : data;
  return row === detectedChangeId;
}

export async function recordInternalFailure(
  input: {
    officeId: string;
    processId: string | null;
    origin: string;
    providerId?: string | null;
    capability?: string | null;
    failureStage: string;
    failureClass: string;
    failureCode: string;
    sourceType: string;
    sourceId?: string | null;
  },
  client: FailureRpcClient = createAdminClient() as unknown as FailureRpcClient
): Promise<string | null> {
  const { data, error } = await client.rpc(
    'phase11_record_failure_event_internal',
    {
      p_office_id: input.officeId,
      p_process_id: input.processId,
      p_origin: input.origin,
      p_provider_id: input.providerId ?? null,
      p_capability: input.capability ?? null,
      p_failure_stage: input.failureStage,
      p_failure_class: input.failureClass,
      p_failure_code: input.failureCode,
      p_context_allowlisted: {
        source: 'phase9',
        capability: input.capability ?? null,
        failure_stage: input.failureStage,
      },
      p_query_execution_id: null,
      p_query_job_id: null,
      p_provider_exchange_id: null,
      p_attempt_number: null,
      p_source_type: input.sourceType,
      p_source_id: input.sourceId ?? null,
    }
  );
  if (error) return null;
  const row = Array.isArray(data) ? data[0] : data;
  return typeof row === 'string' ? row : null;
}

export async function recordComparisonPersistenceFailure(
  input: {
    officeId: string;
    processId: string;
    providerId: string;
    capability: string;
    snapshotId: string;
  },
  client: FailureRpcClient = createAdminClient() as unknown as FailureRpcClient
): Promise<string | null> {
  const { data, error } = await client.rpc(
    'phase11_record_failure_event_internal',
    {
      p_office_id: input.officeId,
      p_process_id: input.processId,
      p_origin: 'comparison',
      p_provider_id: input.providerId,
      p_capability: input.capability,
      p_failure_stage: 'comparison',
      p_failure_class: 'comparison',
      p_failure_code: 'comparison_persistence_failed',
      p_context_allowlisted: {
        source: 'phase10',
        capability: input.capability,
        failure_stage: 'comparison',
      },
      p_query_execution_id: null,
      p_query_job_id: null,
      p_provider_exchange_id: null,
      p_attempt_number: null,
      p_source_type: 'process_comparison',
      p_source_id: input.snapshotId,
    }
  );
  if (error) return null;
  const row = Array.isArray(data) ? data[0] : data;
  return typeof row === 'string' ? row : null;
}
