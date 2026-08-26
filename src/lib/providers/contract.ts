import type { Json } from '@/types/database.types';

export const PROVIDER_CONTRACT_VERSION = 1 as const;

export const PROVIDER_KINDS = [
  'datajud',
  'manual',
  'synthetic',
  'unknown',
] as const;
export type ProviderKind = (typeof PROVIDER_KINDS)[number];

export const PROVIDER_CAPABILITIES = [
  'process_observation',
  'basic_data',
  'movements',
  'parties',
  'publications',
  'documents',
  'sealed_process',
  'manual_evidence',
] as const;
export type ProviderCapability = (typeof PROVIDER_CAPABILITIES)[number];

export const PROVIDER_FAILURE_CODES = [
  'source_unavailable',
  'not_found',
  'not_supported',
  'rate_limited',
  'timeout',
  'technical_failure',
  'manual_review_required',
] as const;
export type ProviderFailureCode = (typeof PROVIDER_FAILURE_CODES)[number];

export type ProviderOperation = 'observe_process';

export type ProviderRole = 'lawyer' | 'operator' | 'reviewer' | 'auditor';

export interface ProviderExecutionContext {
  readonly actorUserId: string;
  readonly officeId: string;
  readonly role: ProviderRole;
  readonly isOwner: boolean;
}

export interface ProviderRequestV1 {
  readonly contractVersion: typeof PROVIDER_CONTRACT_VERSION;
  readonly operation: ProviderOperation;
  readonly capability: ProviderCapability;
  readonly subjectRef: {
    readonly type: 'process';
    readonly value: string;
  };
  readonly requestFingerprint: string;
  readonly correlationId: string;
  readonly requestedAt: string;
  readonly executionContext: ProviderExecutionContext;
}

export interface ProviderIdentity {
  readonly providerId: string;
  readonly providerKind: ProviderKind;
  readonly adapterVersion: string;
  readonly contractVersion: typeof PROVIDER_CONTRACT_VERSION;
}

export interface ProviderDescriptor extends ProviderIdentity {
  readonly displayName: string;
  readonly capabilities: readonly ProviderCapability[];
}

export interface ProviderSourceMetadata {
  readonly sourceType: ProviderKind;
  readonly providerId: string;
  readonly adapterVersion: string;
  readonly contractVersion: typeof PROVIDER_CONTRACT_VERSION;
  readonly observedAt: string;
  readonly durationMs?: number;
}

export interface ProviderEvidence {
  readonly evidenceRef: string;
  readonly evidenceType: 'manual_note' | 'synthetic_fixture';
  readonly observedAt: string;
}

export interface NormalizedMovement {
  readonly movementRef: string;
  readonly date?: string;
  readonly description?: string;
  readonly missingFields: readonly string[];
}

export interface NormalizedPartyObservation {
  readonly partyRef: string;
  readonly role?: string;
  readonly missingFields: readonly string[];
}

export interface NormalizedProcessObservation {
  readonly processRef: string;
  readonly tribunal?: string;
  readonly system?: string;
  readonly movements?: readonly NormalizedMovement[];
  readonly parties?: readonly NormalizedPartyObservation[];
}

export interface ProviderObservationV1 {
  readonly kind: 'observation';
  readonly status: 'observed';
  readonly provider: ProviderIdentity;
  readonly source: ProviderKind;
  readonly contractVersion: typeof PROVIDER_CONTRACT_VERSION;
  readonly capability: ProviderCapability;
  readonly data: NormalizedProcessObservation;
  readonly returnedFields: readonly string[];
  readonly missingFields: readonly string[];
  readonly sourceMetadata: ProviderSourceMetadata;
  readonly correlationId: string;
  readonly evidence?: ProviderEvidence;
}

export interface ProviderFailureV1 {
  readonly kind: 'failure';
  readonly status: ProviderFailureCode;
  readonly provider: ProviderIdentity;
  readonly source: ProviderKind;
  readonly contractVersion: typeof PROVIDER_CONTRACT_VERSION;
  readonly capability: ProviderCapability;
  readonly errorCode: string;
  readonly message: string;
  readonly retryable: boolean;
  readonly retryAfterMs?: number;
  readonly sourceMetadata: ProviderSourceMetadata;
  readonly correlationId: string;
  readonly evidence?: ProviderEvidence;
}

export type ProviderResultV1 = ProviderObservationV1 | ProviderFailureV1;

export interface ProviderAdapter {
  readonly descriptor: ProviderDescriptor;
  observe(
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<ProviderResultV1>;
}

export type JsonCompatibleProviderMetadata = Json;
