import 'server-only';

import { createClient } from '@/lib/supabase/server';
import {
  createDataJudProvider,
  type DataJudExecution,
  type DataJudProviderInput,
  type DataJudTransport,
} from './adapters/datajud-server';
import {
  PROVIDER_CONTRACT_VERSION,
  type ProviderFailureV1,
  type ProviderRequestV1,
  type ProviderResultV1,
} from './contract';
import { failurePolicy, sanitizeProviderMessage } from './errors';
import {
  PAYLOAD_SANITIZATION_VERSION,
  sanitizeRawProviderPayload,
} from './payload';

export {
  MAX_SANITIZED_PAYLOAD_BYTES,
  PAYLOAD_SANITIZATION_VERSION,
  PayloadSanitizationError,
  sanitizeRawProviderPayload,
} from './payload';

function persistenceFailure(
  result: ProviderResultV1,
  errorCode: string
): ProviderFailureV1 {
  return {
    kind: 'failure',
    status: 'technical_failure',
    provider: result.provider,
    source: result.source,
    contractVersion: PROVIDER_CONTRACT_VERSION,
    capability: result.capability,
    errorCode,
    message: sanitizeProviderMessage('technical_failure'),
    ...failurePolicy('technical_failure'),
    sourceMetadata: result.sourceMetadata,
    correlationId: result.correlationId,
  };
}

type ProviderExchangeRpcArgs = {
  p_process_id: string;
  p_provider_id: string;
  p_source: string;
  p_contract_version: number;
  p_subject_ref: string;
  p_correlation_id: string;
  p_request_fingerprint: string;
  p_result_kind: 'observation' | 'failure';
  p_result_status: string;
  p_error_code: string | null;
  p_normalized_result: unknown;
  p_raw_payload: unknown;
  p_sanitization_version: string | null;
  p_received_at: string;
};

type RpcClient = {
  rpc: (
    functionName: string,
    args:
      | ProviderExchangeRpcArgs
      | { p_exchange_id: string }
      | { p_process_id: string }
  ) => Promise<{ data: unknown; error: { message: string } | null }>;
};

function resultRpcArgs(
  processId: string,
  request: ProviderRequestV1,
  execution: DataJudExecution,
  sanitizedPayload: ReturnType<typeof sanitizeRawProviderPayload> | null
): ProviderExchangeRpcArgs {
  const result = execution.result;
  return {
    p_process_id: processId,
    p_provider_id: result.provider.providerId,
    p_source: result.source,
    p_contract_version: result.contractVersion,
    p_subject_ref:
      result.kind === 'observation'
        ? result.data.processRef
        : request.subjectRef.value,
    p_correlation_id: result.correlationId,
    p_request_fingerprint: request.requestFingerprint,
    p_result_kind: result.kind,
    p_result_status: result.status,
    p_error_code: result.kind === 'failure' ? result.errorCode : null,
    p_normalized_result: result.kind === 'observation' ? result : null,
    p_raw_payload: sanitizedPayload?.payload ?? null,
    p_sanitization_version: sanitizedPayload
      ? PAYLOAD_SANITIZATION_VERSION
      : null,
    p_received_at: result.sourceMetadata.observedAt,
  };
}

async function persistExecution(
  processId: string,
  request: ProviderRequestV1,
  execution: DataJudExecution,
  sanitizedPayload: ReturnType<typeof sanitizeRawProviderPayload> | null
): Promise<{ exchangeId: string } | { failure: ProviderFailureV1 }> {
  const supabase = (await createClient()) as unknown as RpcClient;
  const { data, error } = await supabase.rpc(
    'record_provider_exchange',
    resultRpcArgs(processId, request, execution, sanitizedPayload)
  );
  if (error || typeof data !== 'string') {
    return {
      failure: persistenceFailure(
        execution.result,
        'provider_persistence_failed'
      ),
    };
  }
  return { exchangeId: data };
}

export async function observeDataJudAndPersist(
  processId: string,
  request: ProviderRequestV1,
  input?: DataJudProviderInput,
  transport?: DataJudTransport
): Promise<{
  readonly exchangeId?: string;
  readonly result: ProviderResultV1;
}> {
  const provider = createDataJudProvider(transport);
  const supabase = (await createClient()) as unknown as RpcClient;
  const { error: preflightError } = await supabase.rpc(
    'require_provider_process_eligible',
    { p_process_id: processId }
  );
  if (preflightError) {
    return {
      result: {
        kind: 'failure',
        status: 'technical_failure',
        provider: {
          providerId: provider.descriptor.providerId,
          providerKind: provider.descriptor.providerKind,
          adapterVersion: provider.descriptor.adapterVersion,
          contractVersion: provider.descriptor.contractVersion,
        },
        source: 'datajud',
        contractVersion: PROVIDER_CONTRACT_VERSION,
        capability: request.capability,
        errorCode: 'datajud_process_not_eligible',
        message: sanitizeProviderMessage('technical_failure'),
        ...failurePolicy('technical_failure'),
        sourceMetadata: {
          sourceType: 'datajud',
          providerId: provider.descriptor.providerId,
          adapterVersion: provider.descriptor.adapterVersion,
          contractVersion: PROVIDER_CONTRACT_VERSION,
          observedAt: request.requestedAt,
          durationMs: 0,
        },
        correlationId: request.correlationId,
      },
    };
  }
  const execution = await provider.observeWithPayload(request, input);
  let sanitizedPayload: ReturnType<typeof sanitizeRawProviderPayload> | null =
    null;
  if (execution.rawPayload !== undefined) {
    try {
      sanitizedPayload = sanitizeRawProviderPayload(execution.rawPayload);
    } catch {
      const sanitizationFailure = persistenceFailure(
        execution.result,
        'datajud_payload_sanitization_failed'
      );
      const fallbackExecution: DataJudExecution = {
        result: sanitizationFailure,
      };
      const fallback = await persistExecution(
        processId,
        request,
        fallbackExecution,
        null
      );
      if ('failure' in fallback) return { result: fallback.failure };
      return { exchangeId: fallback.exchangeId, result: sanitizationFailure };
    }
  }

  const persisted = await persistExecution(
    processId,
    request,
    execution,
    sanitizedPayload
  );
  if ('failure' in persisted) return { result: persisted.failure };
  return { exchangeId: persisted.exchangeId, result: execution.result };
}

export async function getProviderRawPayload(
  exchangeId: string
): Promise<unknown> {
  const supabase = (await createClient()) as unknown as RpcClient;
  const { data, error } = await supabase.rpc('get_provider_raw_payload', {
    p_exchange_id: exchangeId,
  });
  if (error) {
    throw new Error('Não foi possível acessar a evidência bruta autorizada.');
  }
  return data;
}
