import { createHash } from 'node:crypto';
import { z } from 'zod';
import {
  PROVIDER_CONTRACT_VERSION,
  type NormalizedMovement,
  type NormalizedProcessObservation,
  type ProviderDescriptor,
  type ProviderFailureV1,
  type ProviderIdentity,
  type ProviderObservationV1,
  type ProviderRequestV1,
  type ProviderResultV1,
} from '../contract';
import { failurePolicy, sanitizeProviderMessage } from '../errors';
import {
  DATAJUD_TIMEOUT_MS,
  type DataJudExecution,
  type DataJudProviderAdapter,
  type DataJudTransport,
} from './datajud-core';

export const DATAJUD_PUBLIC_PROVIDER_ID = 'datajud_public';
export const DATAJUD_PUBLIC_ADAPTER_VERSION = '1.0.0';

const providerIdentity: ProviderIdentity = {
  providerId: DATAJUD_PUBLIC_PROVIDER_ID,
  providerKind: 'datajud',
  adapterVersion: DATAJUD_PUBLIC_ADAPTER_VERSION,
  contractVersion: PROVIDER_CONTRACT_VERSION,
};

export const DATAJUD_PUBLIC_DESCRIPTOR: ProviderDescriptor = {
  ...providerIdentity,
  displayName: 'DataJud CNJ (API Pública)',
  capabilities: ['process_observation', 'movements'],
};

function sha256Hex(content: string): string {
  return createHash('sha256').update(content, 'utf8').digest('hex');
}

function failureResult(
  request: ProviderRequestV1,
  code: ProviderFailureV1['status'],
  errorCode: string,
  observedAt: string,
  durationMs: number,
  retryAfterMs?: number
): ProviderFailureV1 {
  const policy = failurePolicy(code);
  return {
    kind: 'failure',
    status: code,
    provider: providerIdentity,
    source: 'datajud',
    contractVersion: PROVIDER_CONTRACT_VERSION,
    capability: request.capability,
    errorCode,
    message: sanitizeProviderMessage(code),
    ...policy,
    ...(retryAfterMs !== undefined ? { retryAfterMs } : {}),
    sourceMetadata: {
      sourceType: 'datajud',
      providerId: DATAJUD_PUBLIC_PROVIDER_ID,
      adapterVersion: DATAJUD_PUBLIC_ADAPTER_VERSION,
      contractVersion: PROVIDER_CONTRACT_VERSION,
      observedAt,
      durationMs,
    },
    correlationId: request.correlationId,
    evidence: {
      evidenceType: 'provider_response',
      evidenceRef: `datajud-public:${sha256Hex(request.correlationId).slice(0, 32)}`,
      observedAt,
    },
  };
}

const rawMovementSchema = z.object({
  codigo: z.union([z.number(), z.string()]).optional(),
  nome: z.string().optional(),
  dataHora: z.string().min(1),
  orgaoJulgador: z
    .object({
      nomeOrgao: z.string().optional(),
      codigoOrgao: z.union([z.number(), z.string()]).optional(),
    })
    .optional(),
  complementosTabelados: z
    .array(
      z.object({
        nome: z.string().optional(),
        descricao: z.string().optional(),
        valor: z.union([z.number(), z.string()]).optional(),
      })
    )
    .optional(),
});

const rawProcessHitSourceSchema = z.object({
  numeroProcesso: z.string().min(1),
  tribunal: z.string().optional(),
  siglaTribunal: z.string().optional(),
  classe: z
    .object({
      codigo: z.union([z.number(), z.string()]).optional(),
      nome: z.string().optional(),
    })
    .optional(),
  grau: z.string().optional(),
  dataHoraUltimaAtualizacao: z.string().optional(),
  movimentos: z.array(rawMovementSchema).optional(),
});

const elasticsearchResponseSchema = z.object({
  hits: z.object({
    total: z.union([
      z.number(),
      z.object({
        value: z.number(),
      }),
    ]),
    hits: z.array(
      z.object({
        _source: rawProcessHitSourceSchema,
      })
    ),
  }),
});

export class DataJudPublicAdapter implements DataJudProviderAdapter {
  readonly descriptor = DATAJUD_PUBLIC_DESCRIPTOR;
  private readonly transport: DataJudTransport;

  constructor(transport: DataJudTransport) {
    this.transport = transport;
  }

  async observe(
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<ProviderResultV1> {
    const execution = await this.observeWithPayload(request, input);
    return execution.result;
  }

  async observeWithPayload(
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<DataJudExecution> {
    const start = Date.now();
    const transportResult = await this.transport.execute(
      {
        subjectRef: request.subjectRef.value,
        correlationId: request.correlationId,
        requestedAt: request.requestedAt,
        timeoutMs: DATAJUD_TIMEOUT_MS,
      },
      input
    );

    const durationMs = Date.now() - start;
    const observedAt = new Date().toISOString();

    if (!('status' in transportResult)) {
      const code = transportResult.code;
      if (code === 'timeout') {
        return {
          result: failureResult(
            request,
            'timeout',
            'datajud_timeout',
            observedAt,
            durationMs
          ),
        };
      }
      if (code === 'not_configured') {
        return {
          result: failureResult(
            request,
            'technical_failure',
            'datajud_not_configured',
            observedAt,
            durationMs
          ),
        };
      }
      return {
        result: failureResult(
          request,
          'source_unavailable',
          'datajud_source_unavailable',
          observedAt,
          durationMs
        ),
      };
    }

    const { status, body } = transportResult;

    let parsedRetryAfterMs: number | undefined = undefined;
    const rawRetryAfter = transportResult.headers?.['retry-after'];
    if (rawRetryAfter) {
      const parsedSec = parseInt(rawRetryAfter, 10);
      if (!Number.isNaN(parsedSec) && parsedSec >= 0) {
        parsedRetryAfterMs = parsedSec * 1000;
      }
    }

    if (status === 401 || status === 403) {
      return {
        result: failureResult(
          request,
          'technical_failure',
          'datajud_auth_failure',
          observedAt,
          durationMs
        ),
        rawPayload: body,
      };
    }

    if (status === 404) {
      return {
        result: failureResult(
          request,
          'technical_failure',
          'datajud_endpoint_not_supported',
          observedAt,
          durationMs
        ),
        rawPayload: body,
      };
    }

    if (status === 429) {
      return {
        result: failureResult(
          request,
          'rate_limited',
          'datajud_rate_limited',
          observedAt,
          durationMs,
          parsedRetryAfterMs
        ),
        rawPayload: body,
      };
    }

    if (status >= 500) {
      return {
        result: failureResult(
          request,
          'source_unavailable',
          'datajud_source_unavailable',
          observedAt,
          durationMs,
          parsedRetryAfterMs
        ),
        rawPayload: body,
      };
    }

    if (status < 200 || status >= 300) {
      return {
        result: failureResult(
          request,
          'technical_failure',
          'datajud_http_failure',
          observedAt,
          durationMs
        ),
        rawPayload: body,
      };
    }

    const parsedEnvelope = elasticsearchResponseSchema.safeParse(body);
    if (!parsedEnvelope.success) {
      return {
        result: failureResult(
          request,
          'technical_failure',
          'datajud_schema_invalid',
          observedAt,
          durationMs
        ),
        rawPayload: body,
      };
    }

    const totalHits =
      typeof parsedEnvelope.data.hits.total === 'number'
        ? parsedEnvelope.data.hits.total
        : parsedEnvelope.data.hits.total.value;

    if (totalHits === 0 || parsedEnvelope.data.hits.hits.length === 0) {
      return {
        result: failureResult(
          request,
          'not_found',
          'datajud_not_found',
          observedAt,
          durationMs
        ),
        rawPayload: body,
      };
    }

    if (totalHits > 1 || parsedEnvelope.data.hits.hits.length > 1) {
      return {
        result: failureResult(
          request,
          'manual_review_required',
          'datajud_multiple_hits_returned',
          observedAt,
          durationMs
        ),
        rawPayload: body,
      };
    }

    const hitSource = parsedEnvelope.data.hits.hits[0]._source;
    const expectedCnjDigits = request.subjectRef.value.replace(/\D/g, '');
    const actualCnjDigits = hitSource.numeroProcesso.replace(/\D/g, '');

    if (actualCnjDigits !== expectedCnjDigits) {
      return {
        result: failureResult(
          request,
          'technical_failure',
          'datajud_process_mismatch',
          observedAt,
          durationMs
        ),
        rawPayload: body,
      };
    }

    // Process movements with conservative identity & collision detection
    const normalizedMovements: NormalizedMovement[] = [];
    const movementByRef = new Map<string, { desc: string; date: string }>();

    for (const mov of hitSource.movimentos ?? []) {
      const codigoStr = mov.codigo !== undefined ? String(mov.codigo) : '';
      const orgaoStr = mov.orgaoJulgador?.codigoOrgao
        ? String(mov.orgaoJulgador.codigoOrgao)
        : (mov.orgaoJulgador?.nomeOrgao ?? '');

      const identityKey = `${codigoStr}|${mov.dataHora}|${orgaoStr}`;
      const movementRef = sha256Hex(identityKey);

      let desc = mov.nome ?? '';
      if (mov.complementosTabelados && mov.complementosTabelados.length > 0) {
        const compDesc = mov.complementosTabelados
          .map((c) => [c.nome, c.descricao, c.valor].filter(Boolean).join(': '))
          .filter(Boolean)
          .join('; ');
        if (compDesc) {
          desc = desc ? `${desc} (${compDesc})` : compDesc;
        }
      }

      const existing = movementByRef.get(movementRef);
      if (existing) {
        // If exact duplicate, ignore
        if (existing.desc === desc && existing.date === mov.dataHora) {
          continue;
        }
        // Ambiguity collision detected
        return {
          result: failureResult(
            request,
            'manual_review_required',
            'datajud_movement_ambiguity_detected',
            observedAt,
            durationMs
          ),
          rawPayload: body,
        };
      }

      movementByRef.set(movementRef, { desc, date: mov.dataHora });

      normalizedMovements.push({
        movementRef,
        date: mov.dataHora,
        description: desc || undefined,
        missingFields: [],
      });
    }

    const tribunal =
      hitSource.siglaTribunal ?? hitSource.tribunal ?? 'TRIBUNAL_PUBLIC';

    const observationData: NormalizedProcessObservation = {
      processRef: request.subjectRef.value,
      tribunal,
      movements: normalizedMovements,
    };

    let sourceUpdatedAt: string | undefined = undefined;
    if (hitSource.dataHoraUltimaAtualizacao) {
      const parsedTime = Date.parse(hitSource.dataHoraUltimaAtualizacao);
      if (!Number.isNaN(parsedTime)) {
        sourceUpdatedAt = new Date(parsedTime).toISOString();
      }
    }

    const observationResult: ProviderObservationV1 = {
      kind: 'observation',
      status: 'observed',
      provider: providerIdentity,
      source: 'datajud',
      contractVersion: PROVIDER_CONTRACT_VERSION,
      capability: request.capability,
      data: observationData,
      returnedFields: ['processRef', 'tribunal', 'movements'],
      missingFields: ['parties', 'system'],
      sourceMetadata: {
        sourceType: 'datajud',
        providerId: DATAJUD_PUBLIC_PROVIDER_ID,
        adapterVersion: DATAJUD_PUBLIC_ADAPTER_VERSION,
        contractVersion: PROVIDER_CONTRACT_VERSION,
        observedAt,
        sourceUpdatedAt,
        durationMs,
      },
      correlationId: request.correlationId,
      evidence: {
        evidenceType: 'provider_response',
        evidenceRef: `datajud-public:${sha256Hex(request.correlationId).slice(0, 32)}`,
        observedAt,
      },
    };

    return {
      result: observationResult,
      rawPayload: body,
    };
  }
}

export function createDataJudPublicProvider(
  transport: DataJudTransport
): DataJudPublicAdapter {
  return new DataJudPublicAdapter(transport);
}
