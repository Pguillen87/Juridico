import { describe, expect, it } from 'vitest';
import { d022Actions, canPerformAction } from '@/lib/auth/permissions';
import { SYNTHETIC_MANUAL_OBSERVATION } from '@/lib/providers/fixtures';
import {
  PROVIDER_CONTRACT_VERSION,
  assertProviderResult,
  createManualProvider,
  providerFingerprint,
  type ProviderRequestV1,
} from '@/lib/providers';
import { createTestProviderGateway } from '@/lib/providers/registry-test';

const MANUAL_IDENTITY = {
  providerId: 'manual_observation',
  providerKind: 'manual',
  adapterVersion: '1.0.0',
  contractVersion: PROVIDER_CONTRACT_VERSION,
} as const;

function request(
  overrides: Partial<ProviderRequestV1> = {}
): ProviderRequestV1 {
  return {
    contractVersion: PROVIDER_CONTRACT_VERSION,
    operation: 'observe_process',
    capability: 'process_observation',
    subjectRef: { type: 'process', value: 'synthetic-process-001' },
    requestFingerprint: providerFingerprint({
      operation: 'observe_process',
      subjectRef: 'synthetic-process-001',
    }),
    correlationId: 'synthetic-correlation-001',
    requestedAt: '2026-01-01T00:00:00.000Z',
    executionContext: {
      actorUserId: 'synthetic-user-001',
      officeId: 'synthetic-office-001',
      role: 'lawyer',
      isOwner: false,
    },
    ...overrides,
  };
}

describe('ProviderContractV1', () => {
  it('normalizes a manual observation without comparison states', async () => {
    const provider = createManualProvider();
    const result = await provider.observe(request(), {
      ...SYNTHETIC_MANUAL_OBSERVATION,
      system: undefined,
      movements: undefined,
    });

    expect(result.kind).toBe('observation');
    if (result.kind !== 'observation') throw new Error('Resultado inesperado.');
    expect(result.status).toBe('observed');
    expect(result.source).toBe('manual');
    expect(result.missingFields).toContain('system');
    expect(result.missingFields).toContain('movements');
    expect(result.evidence?.evidenceType).toBe('manual_note');
    expect('changed' in result).toBe(false);
    expect('unchanged' in result).toBe(false);
  });

  it('accepts an observation for the exact requested process', async () => {
    const provider = createManualProvider();
    const result = await provider.observe(
      request(),
      SYNTHETIC_MANUAL_OBSERVATION
    );

    expect(result.kind).toBe('observation');
    if (result.kind !== 'observation') throw new Error('Observação esperada.');
    expect(result.data.processRef).toBe('synthetic-process-001');
  });

  it('rejects an observation for a different process', async () => {
    const provider = createManualProvider();
    const result = await provider.observe(request(), {
      ...SYNTHETIC_MANUAL_OBSERVATION,
      processRef: 'synthetic-process-999',
    });

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'manual_review_required',
      errorCode: 'manual_process_mismatch',
      source: 'manual',
    });
    expect(JSON.stringify(result)).not.toContain('unchanged');
    expect(JSON.stringify(result)).not.toContain('not_found');
    if (result.kind !== 'failure') throw new Error('Falha esperada.');
    expect(result.message).toBe(
      'A observação exige revisão manual antes de qualquer decisão.'
    );
  });

  it('keeps incomplete manual evidence as an explicit failure', async () => {
    const provider = createManualProvider();
    const result = await provider.observe(request(), undefined);

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'manual_review_required',
      errorCode: 'manual_evidence_missing',
      retryable: false,
    });
    if (result.kind !== 'failure') throw new Error('Falha esperada.');
    expect(result.message).not.toContain('synthetic');
  });

  it('returns not_supported for an unsupported operation', async () => {
    const provider = createManualProvider();
    const result = await provider.observe(
      request({ operation: 'unsupported_operation' as never }),
      {
        processRef: 'synthetic-process-001',
        evidenceRef: 'x',
        observedAt: '2026-01-01',
      }
    );

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'not_supported',
      errorCode: 'operation_not_supported',
    });
  });

  it('exposes only the declared manual capabilities', () => {
    expect(createManualProvider().descriptor).toMatchObject({
      providerId: 'manual_observation',
      providerKind: 'manual',
      contractVersion: 1,
      capabilities: ['process_observation'],
    });
  });

  it('returns not_supported for an unregistered provider', async () => {
    const gateway = createTestProviderGateway();
    const result = await gateway.observe(
      'provider-that-does-not-exist',
      request()
    );

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'not_supported',
      errorCode: 'provider_not_registered',
    });
  });

  it('returns not_supported when the capability is absent', async () => {
    const gateway = createTestProviderGateway();
    const result = await gateway.observe(
      'manual_observation',
      request({ capability: 'movements' }),
      {
        processRef: 'synthetic-process-001',
        evidenceRef: 'x',
        observedAt: '2026-01-01',
      }
    );

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'not_supported',
      errorCode: 'capability_not_supported',
    });
  });

  it('produces the same fingerprint for reordered object keys', () => {
    expect(providerFingerprint({ b: 2, a: 1 })).toBe(
      providerFingerprint({ a: 1, b: 2 })
    );
  });

  it('does not leak raw values or comparison states in a failure', async () => {
    const result = await createManualProvider().observe(request(), {
      processRef: 'synthetic-process-001',
      evidenceRef: 'secret-like-value-must-not-be-echoed',
      observedAt: 'not-a-date',
    });

    expect(result.kind).toBe('failure');
    expect(JSON.stringify(result)).not.toContain('secret-like-value');
    expect(JSON.stringify(result)).not.toContain('changed');
    expect(JSON.stringify(result)).not.toContain('unchanged');
  });

  it('rejects negative retry metadata at the contract boundary', () => {
    expect(() =>
      assertProviderResult({
        kind: 'failure',
        status: 'timeout',
        provider: MANUAL_IDENTITY,
        source: 'manual',
        contractVersion: PROVIDER_CONTRACT_VERSION,
        capability: 'process_observation',
        errorCode: 'timeout',
        message: 'A fonte não respondeu dentro do tempo permitido.',
        retryable: true,
        retryAfterMs: -1,
        sourceMetadata: {
          sourceType: 'manual',
          providerId: 'manual_observation',
          adapterVersion: '1.0.0',
          contractVersion: PROVIDER_CONTRACT_VERSION,
          observedAt: '2026-01-01T00:00:00.000Z',
        },
        correlationId: 'synthetic-correlation-001',
      })
    ).toThrow('Retry de provider inválido.');
  });

  it('does not invent a ManualProvider entry permission', () => {
    expect(
      d022Actions.some(
        (entry) => (entry.action as string) === 'manual_provider_entry'
      )
    ).toBe(false);
    expect(
      canPerformAction(
        {
          role: 'operator',
          isOwner: false,
          isActive: true,
          officeIsActive: true,
        },
        'manual_reprocess'
      )
    ).toBe(true);
  });

  it('accepts a structurally valid observation at runtime', async () => {
    const provider = createManualProvider();
    const result = await provider.observe(
      request(),
      SYNTHETIC_MANUAL_OBSERVATION
    );

    expect(
      assertProviderResult(result, request(), provider.descriptor)
    ).toEqual(result);
  });

  it('rejects a structurally incoherent observation at runtime', () => {
    expect(() =>
      assertProviderResult({
        kind: 'observation',
        status: 'observed',
        provider: MANUAL_IDENTITY,
        source: 'manual',
        contractVersion: PROVIDER_CONTRACT_VERSION,
        capability: 'process_observation',
        data: { processRef: 'synthetic-process-001' },
        returnedFields: ['processRef', 'tribunal'],
        missingFields: [],
        sourceMetadata: {
          sourceType: 'manual',
          providerId: 'manual_observation',
          adapterVersion: '1.0.0',
          contractVersion: PROVIDER_CONTRACT_VERSION,
          observedAt: '2026-01-01T00:00:00.000Z',
        },
        correlationId: 'synthetic-correlation-001',
        changed: true,
      })
    ).toThrow('Resultado de provider não pode conter estados de comparação.');
  });

  it('rejects a result with an incompatible contract version', () => {
    expect(() =>
      assertProviderResult({
        kind: 'observation',
        status: 'observed',
        provider: MANUAL_IDENTITY,
        source: 'manual',
        contractVersion: 99,
        capability: 'process_observation',
        data: { processRef: 'synthetic-process-001' },
        returnedFields: ['processRef'],
        missingFields: [],
        sourceMetadata: {
          sourceType: 'manual',
          providerId: 'manual_observation',
          adapterVersion: '1.0.0',
          contractVersion: 99,
          observedAt: '2026-01-01T00:00:00.000Z',
        },
        correlationId: 'synthetic-correlation-001',
      } as never)
    ).toThrow('Contrato de provider incompatível.');
  });
});
