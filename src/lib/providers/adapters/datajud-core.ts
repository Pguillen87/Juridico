import { z } from 'zod';
import {
  PROVIDER_CONTRACT_VERSION,
  type ProviderAdapter,
  type ProviderDescriptor,
  type ProviderFailureV1,
  type ProviderObservationV1,
  type ProviderRequestV1,
  type ProviderResultV1,
} from '../contract';
import { failurePolicy, sanitizeProviderMessage } from '../errors';

export const DATAJUD_PROVIDER_ID = 'datajud_sandbox';
export const DATAJUD_ADAPTER_VERSION = '1.0.0';
export const DATAJUD_TIMEOUT_MS = 15_000;
export const DATAJUD_MAX_RESPONSE_BYTES = 256 * 1024;

const DATAJUD_SUCCESS_STATUS = 200;
const DATAJUD_NOT_FOUND_STATUS = 404;
const DATAJUD_RATE_LIMIT_STATUS = 429;
const DATAJUD_MIN_SOURCE_DATE = '2000-01-01T00:00:00.000Z';

const providerIdentity = {
  providerId: DATAJUD_PROVIDER_ID,
  providerKind: 'datajud',
  adapterVersion: DATAJUD_ADAPTER_VERSION,
  contractVersion: PROVIDER_CONTRACT_VERSION,
} as const;

export type DataJudTransportFailureCode =
  'timeout' | 'network' | 'dns' | 'aborted';

export interface DataJudTransportRequest {
  readonly subjectRef: string;
  readonly correlationId: string;
  readonly requestedAt: string;
  readonly timeoutMs: number;
}

export interface DataJudTransportResponse {
  readonly status: number;
  readonly body?: unknown;
  readonly receivedAt?: string;
  readonly headers?: Readonly<Record<string, string>>;
}

export interface DataJudTransportFailure {
  readonly kind: 'transport_failure';
  readonly code: DataJudTransportFailureCode;
}

export type DataJudTransportResult =
  DataJudTransportResponse | DataJudTransportFailure;

export interface DataJudTransport {
  execute(
    request: DataJudTransportRequest,
    input?: unknown
  ): Promise<DataJudTransportResult>;
}

export type DataJudFakeScenario =
  | 'success'
  | 'incomplete'
  | 'without_parties'
  | 'without_movements'
  | 'not_found'
  | 'rate_limited'
  | 'timeout'
  | 'server_error'
  | 'network_error'
  | 'dns_error'
  | 'schema_invalid'
  | 'payload_too_large';

export interface DataJudProviderInput {
  readonly scenario?: DataJudFakeScenario;
  readonly payload?: unknown;
}

export interface DataJudExecution {
  readonly result: ProviderResultV1;
  readonly rawPayload?: unknown;
}

export interface DataJudProviderAdapter extends ProviderAdapter {
  observeWithPayload(
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<DataJudExecution>;
}

const dateString = z
  .string()
  .min(1)
  .refine((value) => !Number.isNaN(Date.parse(value)), 'date');

const movementSchema = z
  .object({
    movementRef: z.string().min(1).max(200),
    date: dateString.optional(),
    description: z.string().min(1).max(2_000).optional(),
  })
  .strict();

const partySchema = z
  .object({
    partyRef: z.string().min(1).max(200),
    role: z.string().min(1).max(120).optional(),
  })
  .strict();

const notFoundPayloadSchema = z
  .object({
    outcome: z.literal('not_found'),
    processRef: z.string().min(1).max(200).optional(),
  })
  .strict();

const observationPayloadSchema = z
  .object({
    outcome: z.literal('observation'),
    processRef: z.string().min(1).max(200),
    tribunal: z.string().min(1).max(200).optional(),
    system: z.string().min(1).max(120).optional(),
    movements: z.array(movementSchema).max(2_000).optional(),
    parties: z.array(partySchema).max(2_000).optional(),
  })
  .strict();

const dataJudPayloadSchema = z.union([
  notFoundPayloadSchema,
  observationPayloadSchema,
]);

const inputSchema = z
  .object({
    scenario: z
      .enum([
        'success',
        'incomplete',
        'without_parties',
        'without_movements',
        'not_found',
        'rate_limited',
        'timeout',
        'server_error',
        'network_error',
        'dns_error',
        'schema_invalid',
        'payload_too_large',
      ])
      .optional(),
    payload: z.unknown().optional(),
  })
  .strict();

const descriptor: ProviderDescriptor = {
  providerId: DATAJUD_PROVIDER_ID,
  providerKind: 'datajud',
  displayName: 'DataJud (sandbox sintético)',
  adapterVersion: DATAJUD_ADAPTER_VERSION,
  contractVersion: PROVIDER_CONTRACT_VERSION,
  capabilities: ['process_observation', 'basic_data', 'movements', 'parties'],
};

function sourceMetadata(durationMs: number, observedAt: string) {
  return {
    sourceType: 'datajud' as const,
    providerId: DATAJUD_PROVIDER_ID,
    adapterVersion: DATAJUD_ADAPTER_VERSION,
    contractVersion: PROVIDER_CONTRACT_VERSION,
    observedAt,
    durationMs: Math.max(0, Math.round(durationMs)),
  };
}

function failure(
  request: ProviderRequestV1,
  code: ProviderFailureV1['status'],
  errorCode: string,
  durationMs: number,
  observedAt: string
): ProviderFailureV1 {
  return {
    kind: 'failure',
    status: code,
    provider: providerIdentity,
    source: 'datajud',
    contractVersion: PROVIDER_CONTRACT_VERSION,
    capability: request.capability,
    errorCode,
    message: sanitizeProviderMessage(code),
    ...failurePolicy(code),
    sourceMetadata: sourceMetadata(durationMs, observedAt),
    correlationId: request.correlationId,
  };
}

function validObservedAt(value: string | undefined, fallback: string): string {
  const candidate = value ?? fallback;
  if (Number.isNaN(Date.parse(candidate))) return fallback;
  const normalized = new Date(candidate).toISOString();
  return normalized < DATAJUD_MIN_SOURCE_DATE ? fallback : normalized;
}

function serializedByteLength(value: unknown): number {
  try {
    return new TextEncoder().encode(JSON.stringify(value)).byteLength;
  } catch {
    return DATAJUD_MAX_RESPONSE_BYTES + 1;
  }
}

function isTransportFailure(
  value: DataJudTransportResult
): value is DataJudTransportFailure {
  return (
    typeof value === 'object' &&
    value !== null &&
    'kind' in value &&
    value.kind === 'transport_failure'
  );
}

function providerInput(value: unknown): DataJudProviderInput | null {
  if (value === undefined) return { scenario: 'success' };
  const parsed = inputSchema.safeParse(value);
  return parsed.success ? parsed.data : null;
}

function normalizedObservation(
  request: ProviderRequestV1,
  payload: z.infer<typeof observationPayloadSchema>,
  durationMs: number,
  observedAt: string
): ProviderObservationV1 {
  const movements = payload.movements?.map((movement) => ({
    movementRef: movement.movementRef,
    ...(movement.date ? { date: new Date(movement.date).toISOString() } : {}),
    ...(movement.description ? { description: movement.description } : {}),
    missingFields: [
      ...(movement.date ? [] : ['date']),
      ...(movement.description ? [] : ['description']),
    ],
  }));
  const parties = payload.parties?.map((party) => ({
    partyRef: party.partyRef,
    ...(party.role ? { role: party.role } : {}),
    missingFields: party.role ? [] : ['role'],
  }));
  const data = {
    processRef: payload.processRef,
    ...(payload.tribunal ? { tribunal: payload.tribunal } : {}),
    ...(payload.system ? { system: payload.system } : {}),
    ...(movements ? { movements } : {}),
    ...(parties ? { parties } : {}),
  };
  const returnedFields = [
    'processRef',
    ...(payload.tribunal ? ['tribunal'] : []),
    ...(payload.system ? ['system'] : []),
    ...(movements ? ['movements'] : []),
    ...(parties ? ['parties'] : []),
  ];
  const missingFields = [
    ...(payload.tribunal ? [] : ['tribunal']),
    ...(payload.system ? [] : ['system']),
    ...(movements ? [] : ['movements']),
    ...(parties ? [] : ['parties']),
  ];
  return {
    kind: 'observation',
    status: 'observed',
    provider: providerIdentity,
    source: 'datajud',
    contractVersion: PROVIDER_CONTRACT_VERSION,
    capability: request.capability,
    data,
    returnedFields,
    missingFields,
    sourceMetadata: sourceMetadata(durationMs, observedAt),
    correlationId: request.correlationId,
    evidence: {
      evidenceRef: `datajud-fixture:${request.correlationId}`,
      evidenceType: 'synthetic_fixture',
      observedAt,
    },
  };
}

function fakePayload(
  request: DataJudTransportRequest,
  scenario: DataJudFakeScenario
): unknown {
  if (scenario === 'not_found') {
    return { outcome: 'not_found', processRef: request.subjectRef };
  }
  if (scenario === 'schema_invalid') {
    return {
      outcome: 'observation',
      processRef: request.subjectRef,
      unexpected: true,
    };
  }
  if (scenario === 'payload_too_large') {
    return {
      outcome: 'observation',
      processRef: request.subjectRef,
      movements: [
        {
          movementRef: 'synthetic-movement-large',
          description: 'x'.repeat(DATAJUD_MAX_RESPONSE_BYTES),
        },
      ],
    };
  }
  return {
    outcome: 'observation',
    processRef: request.subjectRef,
    tribunal: 'TJ-SYNTHETIC',
    ...(scenario === 'incomplete' ? {} : { system: 'synthetic-system' }),
    ...(scenario === 'without_movements'
      ? {}
      : {
          movements: [
            {
              movementRef: 'synthetic-movement-001',
              date: '2026-01-01T10:00:00.000Z',
              description: 'Movimentação sintética para teste.',
            },
          ],
        }),
    ...(scenario === 'without_parties'
      ? {}
      : {
          parties: [{ partyRef: 'synthetic-party-001', role: 'plaintiff' }],
        }),
  };
}

export function createFakeDataJudTransport(): DataJudTransport {
  return {
    async execute(request, input): Promise<DataJudTransportResult> {
      const parsed = inputSchema.safeParse(input ?? {});
      const scenario: DataJudFakeScenario = parsed.success
        ? (parsed.data.scenario ?? 'success')
        : 'schema_invalid';
      if (scenario === 'timeout')
        return { kind: 'transport_failure', code: 'timeout' };
      if (scenario === 'network_error')
        return { kind: 'transport_failure', code: 'network' };
      if (scenario === 'dns_error')
        return { kind: 'transport_failure', code: 'dns' };
      if (scenario === 'rate_limited') {
        return {
          status: DATAJUD_RATE_LIMIT_STATUS,
          headers: { 'retry-after': '60' },
          body: { error: 'synthetic rate limit' },
        };
      }
      if (scenario === 'server_error') {
        return { status: 503, body: { error: 'synthetic upstream failure' } };
      }
      if (scenario === 'not_found') {
        return {
          status: DATAJUD_NOT_FOUND_STATUS,
          body: fakePayload(request, scenario),
        };
      }
      if (parsed.success && parsed.data.payload !== undefined) {
        return { status: DATAJUD_SUCCESS_STATUS, body: parsed.data.payload };
      }
      return {
        status: DATAJUD_SUCCESS_STATUS,
        body: fakePayload(request, scenario),
      };
    },
  };
}

export function createDataJudProvider(
  transport: DataJudTransport = createFakeDataJudTransport()
): DataJudProviderAdapter {
  const observeWithPayload = async (
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<DataJudExecution> => {
    const startedAt = Date.now();
    const observedAtFallback = validObservedAt(undefined, request.requestedAt);
    if (request.operation !== 'observe_process') {
      return {
        result: failure(
          request,
          'not_supported',
          'operation_not_supported',
          Date.now() - startedAt,
          observedAtFallback
        ),
      };
    }
    if (!descriptor.capabilities.includes(request.capability)) {
      return {
        result: failure(
          request,
          'not_supported',
          'capability_not_supported',
          Date.now() - startedAt,
          observedAtFallback
        ),
      };
    }

    const parsedInput = providerInput(input);
    if (parsedInput === null) {
      return {
        result: failure(
          request,
          'technical_failure',
          'datajud_input_schema_invalid',
          Date.now() - startedAt,
          observedAtFallback
        ),
      };
    }
    const transportResult = await transport.execute(
      {
        subjectRef: request.subjectRef.value,
        correlationId: request.correlationId,
        requestedAt: request.requestedAt,
        timeoutMs: DATAJUD_TIMEOUT_MS,
      },
      parsedInput
    );
    const durationMs = Date.now() - startedAt;
    const observedAt = validObservedAt(
      'receivedAt' in transportResult ? transportResult.receivedAt : undefined,
      request.requestedAt
    );
    const rawPayload = isTransportFailure(transportResult)
      ? undefined
      : transportResult.body;

    if (isTransportFailure(transportResult)) {
      if (
        transportResult.code === 'timeout' ||
        transportResult.code === 'aborted'
      ) {
        return {
          result: failure(
            request,
            'timeout',
            'datajud_timeout',
            durationMs,
            observedAt
          ),
        };
      }
      return {
        result: failure(
          request,
          'source_unavailable',
          transportResult.code === 'dns'
            ? 'datajud_dns_failure'
            : 'datajud_network_failure',
          durationMs,
          observedAt
        ),
      };
    }
    if (transportResult.status === DATAJUD_RATE_LIMIT_STATUS) {
      return {
        result: failure(
          request,
          'rate_limited',
          'datajud_rate_limited',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }
    if (transportResult.status >= 500 && transportResult.status <= 599) {
      return {
        result: failure(
          request,
          'source_unavailable',
          'datajud_source_unavailable',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }
    if (transportResult.status === DATAJUD_NOT_FOUND_STATUS) {
      return {
        result: failure(
          request,
          'not_found',
          'datajud_not_found',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }
    if (transportResult.status !== DATAJUD_SUCCESS_STATUS) {
      return {
        result: failure(
          request,
          'technical_failure',
          'datajud_http_failure',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }
    if (
      serializedByteLength(transportResult.body) > DATAJUD_MAX_RESPONSE_BYTES
    ) {
      return {
        result: failure(
          request,
          'technical_failure',
          'datajud_payload_too_large',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }

    const payload = dataJudPayloadSchema.safeParse(transportResult.body);
    if (!payload.success) {
      return {
        result: failure(
          request,
          'technical_failure',
          'datajud_schema_invalid',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }
    if (payload.data.outcome === 'not_found') {
      return {
        result: failure(
          request,
          'not_found',
          'datajud_not_found',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }
    if (payload.data.processRef !== request.subjectRef.value) {
      return {
        result: failure(
          request,
          'technical_failure',
          'datajud_process_mismatch',
          durationMs,
          observedAt
        ),
        rawPayload,
      };
    }
    return {
      result: normalizedObservation(
        request,
        payload.data,
        durationMs,
        observedAt
      ),
      rawPayload,
    };
  };

  return {
    descriptor,
    observe: async (request, input) =>
      (await observeWithPayload(request, input)).result,
    observeWithPayload,
  };
}

export function getDataJudDescriptor(): ProviderDescriptor {
  return descriptor;
}
