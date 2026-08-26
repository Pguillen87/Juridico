import {
  PROVIDER_CONTRACT_VERSION,
  type ProviderAdapter,
  type ProviderDescriptor,
  type ProviderFailureV1,
  type ProviderObservationV1,
  type ProviderRequestV1,
} from '../contract';
import { failurePolicy, sanitizeProviderMessage } from '../errors';

export interface ManualObservationInput {
  readonly processRef: string;
  readonly evidenceRef: string;
  readonly observedAt: string;
  readonly tribunal?: string;
  readonly system?: string;
  readonly movements?: readonly {
    readonly movementRef: string;
    readonly date?: string;
    readonly description?: string;
  }[];
}

const descriptor: ProviderDescriptor = {
  providerId: 'manual_observation',
  providerKind: 'manual',
  displayName: 'Observação manual',
  adapterVersion: '1.0.0',
  contractVersion: PROVIDER_CONTRACT_VERSION,
  capabilities: ['process_observation'],
};

const providerIdentity = {
  providerId: descriptor.providerId,
  providerKind: descriptor.providerKind,
  adapterVersion: descriptor.adapterVersion,
  contractVersion: descriptor.contractVersion,
} as const;

function failure(
  request: ProviderRequestV1,
  code: ProviderFailureV1['status'],
  errorCode: string
): ProviderFailureV1 {
  return {
    kind: 'failure',
    status: code,
    provider: providerIdentity,
    source: 'manual',
    contractVersion: PROVIDER_CONTRACT_VERSION,
    capability: request.capability,
    errorCode,
    message: sanitizeProviderMessage(code),
    ...failurePolicy(code),
    sourceMetadata: {
      sourceType: 'manual',
      providerId: descriptor.providerId,
      adapterVersion: descriptor.adapterVersion,
      contractVersion: PROVIDER_CONTRACT_VERSION,
      observedAt: request.requestedAt,
      durationMs: 0,
    },
    correlationId: request.correlationId,
  };
}

function isManualInput(input: unknown): input is ManualObservationInput {
  if (!input || typeof input !== 'object') return false;
  const value = input as Partial<ManualObservationInput>;
  return (
    typeof value.processRef === 'string' &&
    value.processRef.length > 0 &&
    typeof value.evidenceRef === 'string' &&
    value.evidenceRef.length > 0 &&
    typeof value.observedAt === 'string' &&
    !Number.isNaN(Date.parse(value.observedAt))
  );
}

export function createManualProvider(): ProviderAdapter {
  return {
    descriptor,
    async observe(
      request,
      input
    ): Promise<ProviderObservationV1 | ProviderFailureV1> {
      if (request.operation !== 'observe_process') {
        return failure(request, 'not_supported', 'operation_not_supported');
      }
      if (request.capability !== 'process_observation') {
        return failure(request, 'not_supported', 'capability_not_supported');
      }
      if (!isManualInput(input)) {
        return failure(
          request,
          'manual_review_required',
          'manual_evidence_missing'
        );
      }
      const manual = input as ManualObservationInput;
      if (manual.processRef !== request.subjectRef.value) {
        return failure(
          request,
          'manual_review_required',
          'manual_process_mismatch'
        );
      }
      const movements = manual.movements?.map((movement) => ({
        movementRef: movement.movementRef,
        ...(movement.date ? { date: movement.date } : {}),
        ...(movement.description ? { description: movement.description } : {}),
        missingFields: [
          ...(movement.date ? [] : ['date']),
          ...(movement.description ? [] : ['description']),
        ],
      }));
      const returnedFields = [
        'processRef',
        ...(manual.tribunal ? ['tribunal'] : []),
        ...(manual.system ? ['system'] : []),
        ...(movements ? ['movements'] : []),
      ];
      const missingFields = [
        ...(manual.tribunal ? [] : ['tribunal']),
        ...(manual.system ? [] : ['system']),
        ...(movements ? [] : ['movements']),
      ];
      return {
        kind: 'observation',
        status: 'observed',
        provider: providerIdentity,
        source: 'manual',
        contractVersion: PROVIDER_CONTRACT_VERSION,
        capability: request.capability,
        data: {
          processRef: manual.processRef,
          ...(manual.tribunal ? { tribunal: manual.tribunal } : {}),
          ...(manual.system ? { system: manual.system } : {}),
          ...(movements ? { movements } : {}),
        },
        returnedFields,
        missingFields,
        sourceMetadata: {
          sourceType: 'manual',
          providerId: descriptor.providerId,
          adapterVersion: descriptor.adapterVersion,
          contractVersion: PROVIDER_CONTRACT_VERSION,
          observedAt: manual.observedAt,
          durationMs: 0,
        },
        correlationId: request.correlationId,
        evidence: {
          evidenceRef: manual.evidenceRef,
          evidenceType: 'manual_note',
          observedAt: manual.observedAt,
        },
      };
    },
  };
}
