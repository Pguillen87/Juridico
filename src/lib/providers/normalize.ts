import {
  PROVIDER_CAPABILITIES,
  PROVIDER_CONTRACT_VERSION,
  PROVIDER_KINDS,
  type ProviderDescriptor,
  type ProviderRequestV1,
  type ProviderResultV1,
} from './contract';
import {
  failurePolicy,
  isProviderErrorCode,
  isProviderFailureCode,
  sanitizeProviderMessage,
} from './errors';

const RESULT_KEYS = {
  observation: new Set([
    'kind',
    'status',
    'provider',
    'source',
    'contractVersion',
    'capability',
    'data',
    'returnedFields',
    'missingFields',
    'sourceMetadata',
    'correlationId',
    'evidence',
  ]),
  failure: new Set([
    'kind',
    'status',
    'provider',
    'source',
    'contractVersion',
    'capability',
    'errorCode',
    'message',
    'retryable',
    'retryAfterMs',
    'sourceMetadata',
    'correlationId',
    'evidence',
  ]),
} as const;
const IDENTITY_KEYS = new Set([
  'providerId',
  'providerKind',
  'adapterVersion',
  'contractVersion',
]);
const METADATA_KEYS = new Set([
  'sourceType',
  'providerId',
  'adapterVersion',
  'contractVersion',
  'observedAt',
  'durationMs',
]);
const DATA_KEYS = new Set([
  'processRef',
  'tribunal',
  'system',
  'movements',
  'parties',
]);
const ITEM_KEYS = new Set([
  'movementRef',
  'partyRef',
  'role',
  'date',
  'description',
  'missingFields',
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(
  value: Record<string, unknown>,
  allowed: ReadonlySet<string>,
  message: string
): void {
  if (Object.keys(value).some((key) => !allowed.has(key)))
    throw new Error(message);
}

function nonEmpty(value: unknown, message: string): asserts value is string {
  if (typeof value !== 'string' || value.trim() === '')
    throw new Error(message);
}

function isoDate(value: unknown, message: string): asserts value is string {
  nonEmpty(value, message);
  if (Number.isNaN(Date.parse(value))) throw new Error(message);
}

function allowlisted<T extends string>(
  value: unknown,
  values: readonly T[],
  message: string
): asserts value is T {
  if (typeof value !== 'string' || !values.includes(value as T))
    throw new Error(message);
}

function stringList(
  value: unknown,
  message: string
): asserts value is string[] {
  if (
    !Array.isArray(value) ||
    value.some((entry) => typeof entry !== 'string' || entry.trim() === '') ||
    new Set(value).size !== value.length
  ) {
    throw new Error(message);
  }
}

function forbidComparisonFields(
  value: unknown,
  seen = new Set<object>()
): void {
  if (Array.isArray(value)) {
    value.forEach((entry) => forbidComparisonFields(entry, seen));
    return;
  }
  if (!isRecord(value) || seen.has(value)) return;
  seen.add(value);
  for (const [key, entry] of Object.entries(value)) {
    if (key === 'changed' || key === 'unchanged') {
      throw new Error(
        'Resultado de provider não pode conter estados de comparação.'
      );
    }
    forbidComparisonFields(entry, seen);
  }
}

function identity(
  value: unknown,
  message: string
): ProviderResultV1['provider'] {
  if (!isRecord(value)) throw new Error(message);
  exactKeys(value, IDENTITY_KEYS, message);
  nonEmpty(value.providerId, message);
  allowlisted(value.providerKind, PROVIDER_KINDS, message);
  nonEmpty(value.adapterVersion, message);
  if (value.contractVersion !== PROVIDER_CONTRACT_VERSION)
    throw new Error(message);
  return value as unknown as ProviderResultV1['provider'];
}

function sameIdentity(
  value: ProviderResultV1['provider'],
  descriptor?: ProviderDescriptor
): void {
  if (!descriptor) return;
  if (
    value.providerId !== descriptor.providerId ||
    value.providerKind !== descriptor.providerKind ||
    value.adapterVersion !== descriptor.adapterVersion ||
    value.contractVersion !== descriptor.contractVersion
  ) {
    throw new Error('Provider do resultado não corresponde ao descriptor.');
  }
}

function sourceMetadata(
  value: unknown,
  provider: ProviderResultV1['provider'],
  source: ProviderResultV1['source']
): void {
  if (!isRecord(value))
    throw new Error('Metadata de origem de provider inválida.');
  exactKeys(value, METADATA_KEYS, 'Metadata de origem de provider inválida.');
  allowlisted(
    value.sourceType,
    PROVIDER_KINDS,
    'Metadata de origem de provider inválida.'
  );
  nonEmpty(value.providerId, 'Metadata de origem de provider inválida.');
  nonEmpty(value.adapterVersion, 'Metadata de origem de provider inválida.');
  if (value.contractVersion !== PROVIDER_CONTRACT_VERSION) {
    throw new Error('Metadata de origem de provider inválida.');
  }
  isoDate(value.observedAt, 'Metadata de origem de provider inválida.');
  if (
    value.durationMs !== undefined &&
    (typeof value.durationMs !== 'number' ||
      !Number.isFinite(value.durationMs) ||
      value.durationMs < 0)
  ) {
    throw new Error('Metadata de origem de provider inválida.');
  }
  if (
    value.sourceType !== source ||
    value.providerId !== provider.providerId ||
    value.adapterVersion !== provider.adapterVersion
  ) {
    throw new Error('Metadata de origem de provider inconsistente.');
  }
}

function evidence(value: unknown): void {
  if (value === undefined) return;
  if (!isRecord(value)) throw new Error('Evidência de provider inválida.');
  exactKeys(
    value,
    new Set(['evidenceRef', 'evidenceType', 'observedAt']),
    'Evidência de provider inválida.'
  );
  nonEmpty(value.evidenceRef, 'Evidência de provider inválida.');
  allowlisted(
    value.evidenceType,
    ['manual_note', 'synthetic_fixture'],
    'Evidência de provider inválida.'
  );
  isoDate(value.observedAt, 'Evidência de provider inválida.');
}

function normalizedItems(
  value: unknown,
  key: 'movementRef' | 'partyRef'
): void {
  if (!Array.isArray(value))
    throw new Error('Lista normalizada de provider inválida.');
  for (const item of value) {
    if (!isRecord(item))
      throw new Error('Item normalizado de provider inválido.');
    exactKeys(item, ITEM_KEYS, 'Item normalizado de provider inválido.');
    nonEmpty(item[key], 'Item normalizado de provider inválido.');
    stringList(item.missingFields, 'missingFields normalizado inválido.');
  }
}

function observationData(
  value: unknown,
  returnedFields: unknown,
  missingFields: unknown,
  request?: ProviderRequestV1
): void {
  if (!isRecord(value)) throw new Error('Dados de observação inválidos.');
  exactKeys(value, DATA_KEYS, 'Dados de observação inválidos.');
  nonEmpty(value.processRef, 'Dados de observação inválidos.');
  if (request && value.processRef !== request.subjectRef.value) {
    throw new Error('Observação não corresponde ao processo solicitado.');
  }
  stringList(returnedFields, 'returnedFields de observação inválido.');
  stringList(missingFields, 'missingFields de observação inválido.');
  const fields = new Set([
    'processRef',
    'tribunal',
    'system',
    'movements',
    'parties',
  ]);
  const returned = returnedFields as string[];
  const missing = missingFields as string[];
  if (
    returned.some((field) => !fields.has(field)) ||
    missing.some((field) => !fields.has(field)) ||
    returned.some((field) => missing.includes(field)) ||
    !returned.includes('processRef') ||
    missing.includes('processRef')
  ) {
    throw new Error('Campos de observação são inconsistentes.');
  }
  for (const field of ['tribunal', 'system', 'movements', 'parties']) {
    const present = value[field] !== undefined;
    if (
      present !== returned.includes(field) ||
      (present && missing.includes(field))
    ) {
      throw new Error('Campos de observação são inconsistentes.');
    }
  }
  if (value.movements !== undefined)
    normalizedItems(value.movements, 'movementRef');
  if (value.parties !== undefined) normalizedItems(value.parties, 'partyRef');
}

function observation(
  result: Record<string, unknown>,
  request?: ProviderRequestV1,
  descriptor?: ProviderDescriptor
): void {
  exactKeys(
    result,
    RESULT_KEYS.observation,
    'Resultado de observação possui campos não permitidos.'
  );
  if (result.status !== 'observed')
    throw new Error('Observação de provider com status inválido.');
  const provider = identity(
    result.provider,
    'Provider da observação inválido.'
  );
  sameIdentity(provider, descriptor);
  allowlisted(result.source, PROVIDER_KINDS, 'Source de provider inválido.');
  if (provider.providerKind !== result.source)
    throw new Error('Source e provider incompatíveis.');
  if (result.contractVersion !== PROVIDER_CONTRACT_VERSION)
    throw new Error('Contrato de provider incompatível.');
  allowlisted(
    result.capability,
    PROVIDER_CAPABILITIES,
    'Capability de provider inválida.'
  );
  if (request && result.capability !== request.capability)
    throw new Error('Capability não corresponde à request.');
  if (
    descriptor &&
    !descriptor.capabilities.includes(result.capability as never)
  ) {
    throw new Error('Capability não pertence ao provider.');
  }
  nonEmpty(result.correlationId, 'CorrelationId de provider inválido.');
  observationData(
    result.data,
    result.returnedFields,
    result.missingFields,
    request
  );
  sourceMetadata(
    result.sourceMetadata,
    provider,
    result.source as ProviderResultV1['source']
  );
  evidence(result.evidence);
}

function failure(
  result: Record<string, unknown>,
  request?: ProviderRequestV1,
  descriptor?: ProviderDescriptor
): void {
  exactKeys(
    result,
    RESULT_KEYS.failure,
    'Resultado de falha possui campos não permitidos.'
  );
  const status = result.status;
  if (typeof status !== 'string' || !isProviderFailureCode(status)) {
    throw new Error('Status de falha de provider inválido.');
  }
  const provider = identity(result.provider, 'Provider da falha inválido.');
  sameIdentity(provider, descriptor);
  allowlisted(result.source, PROVIDER_KINDS, 'Source de provider inválido.');
  if (provider.providerKind !== result.source)
    throw new Error('Source e provider incompatíveis.');
  if (result.contractVersion !== PROVIDER_CONTRACT_VERSION)
    throw new Error('Contrato de provider incompatível.');
  allowlisted(
    result.capability,
    PROVIDER_CAPABILITIES,
    'Capability de provider inválida.'
  );
  if (request && result.capability !== request.capability)
    throw new Error('Capability não corresponde à request.');
  if (
    descriptor &&
    !descriptor.capabilities.includes(result.capability as never)
  ) {
    throw new Error('Capability não pertence ao provider.');
  }
  if (
    typeof result.errorCode !== 'string' ||
    !isProviderErrorCode(result.errorCode)
  ) {
    throw new Error('Código de erro de provider inválido.');
  }
  if (result.message !== sanitizeProviderMessage(status)) {
    throw new Error('Mensagem de falha de provider não é sanitizada.');
  }
  const policy = failurePolicy(status);
  if (result.retryable !== policy.retryable)
    throw new Error('Política de retry de provider inconsistente.');
  if (
    result.retryAfterMs !== undefined &&
    (typeof result.retryAfterMs !== 'number' ||
      !Number.isFinite(result.retryAfterMs) ||
      result.retryAfterMs < 0)
  ) {
    throw new Error('Retry de provider inválido.');
  }
  if (policy.retryAfterMs === undefined && result.retryAfterMs !== undefined) {
    throw new Error('RetryAfterMs não permitido para esta falha.');
  }
  if (
    policy.retryAfterMs !== undefined &&
    result.retryAfterMs !== policy.retryAfterMs
  ) {
    throw new Error('RetryAfterMs de provider inconsistente.');
  }
  nonEmpty(result.correlationId, 'CorrelationId de provider inválido.');
  sourceMetadata(
    result.sourceMetadata,
    provider,
    result.source as ProviderResultV1['source']
  );
  evidence(result.evidence);
}

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
  result: unknown,
  request?: ProviderRequestV1,
  descriptor?: ProviderDescriptor
): ProviderResultV1 {
  forbidComparisonFields(result);
  if (!isRecord(result)) throw new Error('Resultado de provider inválido.');
  if (result.contractVersion !== PROVIDER_CONTRACT_VERSION) {
    throw new Error('Contrato de provider incompatível.');
  }
  if (result.kind === 'observation') observation(result, request, descriptor);
  else if (result.kind === 'failure') failure(result, request, descriptor);
  else throw new Error('Ramo de resultado de provider inválido.');
  return result as unknown as ProviderResultV1;
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
