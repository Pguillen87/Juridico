import { describe, expect, it, vi } from 'vitest';
import {
  DATAJUD_MAX_RESPONSE_BYTES,
  DATAJUD_PROVIDER_ID,
  DATAJUD_TIMEOUT_MS,
  createDataJudProvider,
  createFakeDataJudTransport,
  type DataJudTransport,
  type DataJudTransportRequest,
} from '@/lib/providers/adapters/datajud-core';
import {
  PROVIDER_CONTRACT_VERSION,
  assertProviderResult,
  providerFingerprint,
  type ProviderRequestV1,
} from '@/lib/providers';
import { createTestProviderGateway } from '@/lib/providers/registry-test';

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
    correlationId: 'synthetic-datajud-correlation-001',
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

function responseTransport(
  response: Awaited<ReturnType<DataJudTransport['execute']>>
): DataJudTransport {
  return {
    execute: vi.fn(async () => response),
  };
}

describe('DataJudProvider com transporte sintético', () => {
  it('normaliza uma observação válida sem estados de comparação', async () => {
    const provider = createDataJudProvider();
    const result = await provider.observe(request(), { scenario: 'success' });

    expect(result.kind).toBe('observation');
    if (result.kind !== 'observation') throw new Error('Observação esperada.');
    expect(result.provider.providerId).toBe(DATAJUD_PROVIDER_ID);
    expect(result.source).toBe('datajud');
    expect(result.data.processRef).toBe('synthetic-process-001');
    expect(result.data.movements?.[0]?.date).toBe('2026-01-01T10:00:00.000Z');
    expect(result.data.parties?.[0]?.partyRef).toBe('synthetic-party-001');
    expect(result.evidence?.evidenceType).toBe('synthetic_fixture');
    expect('changed' in result).toBe(false);
    expect('unchanged' in result).toBe(false);
    expect(
      assertProviderResult(result, request(), provider.descriptor)
    ).toEqual(result);
  });

  it('preserva missing fields em resposta incompleta', async () => {
    const result = await createDataJudProvider().observe(request(), {
      scenario: 'incomplete',
    });

    expect(result.kind).toBe('observation');
    if (result.kind !== 'observation') throw new Error('Observação esperada.');
    expect(result.missingFields).toContain('system');
    expect(result.returnedFields).not.toContain('system');
  });

  it('aceita ausência de partes e de movimentos sem inventar dados', async () => {
    const withoutParties = await createDataJudProvider().observe(request(), {
      scenario: 'without_parties',
    });
    const withoutMovements = await createDataJudProvider().observe(request(), {
      scenario: 'without_movements',
    });

    expect(withoutParties.kind).toBe('observation');
    expect(withoutMovements.kind).toBe('observation');
    if (
      withoutParties.kind !== 'observation' ||
      withoutMovements.kind !== 'observation'
    ) {
      throw new Error('Observações esperadas.');
    }
    expect(withoutParties.data.parties).toBeUndefined();
    expect(withoutParties.missingFields).toContain('parties');
    expect(withoutMovements.data.movements).toBeUndefined();
    expect(withoutMovements.missingFields).toContain('movements');
  });

  it('classifica HTTP 429 sem expor o corpo', async () => {
    const result = await createDataJudProvider().observe(request(), {
      scenario: 'rate_limited',
    });

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'rate_limited',
      errorCode: 'datajud_rate_limited',
      retryable: true,
      retryAfterMs: 60_000,
    });
    expect(JSON.stringify(result)).not.toContain('synthetic rate limit');
  });

  it('classifica timeout e não produz observação vazia', async () => {
    const result = await createDataJudProvider().observe(request(), {
      scenario: 'timeout',
    });

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'timeout',
      errorCode: 'datajud_timeout',
      retryable: true,
    });
    expect(result.kind).toBe('failure');
  });

  it('classifica 5xx como source_unavailable', async () => {
    const result = await createDataJudProvider().observe(request(), {
      scenario: 'server_error',
    });

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'source_unavailable',
      errorCode: 'datajud_source_unavailable',
      retryable: true,
    });
  });

  it('classifica not_found separadamente de unchanged', async () => {
    const result = await createDataJudProvider().observe(request(), {
      scenario: 'not_found',
    });

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'not_found',
      errorCode: 'datajud_not_found',
      retryable: false,
    });
    expect(JSON.stringify(result)).not.toContain('unchanged');
  });

  it('classifica network e DNS como source_unavailable', async () => {
    const network = await createDataJudProvider().observe(request(), {
      scenario: 'network_error',
    });
    const dns = await createDataJudProvider().observe(request(), {
      scenario: 'dns_error',
    });

    expect(network).toMatchObject({
      kind: 'failure',
      status: 'source_unavailable',
      errorCode: 'datajud_network_failure',
    });
    expect(dns).toMatchObject({
      kind: 'failure',
      status: 'source_unavailable',
      errorCode: 'datajud_dns_failure',
    });
  });

  it('classifica schema inválido, mismatch e payload excessivo como technical_failure', async () => {
    const invalidSchema = await createDataJudProvider().observe(request(), {
      scenario: 'schema_invalid',
    });
    const mismatch = await createDataJudProvider().observe(request(), {
      payload: {
        outcome: 'observation',
        processRef: 'synthetic-process-999',
      },
    });
    const tooLarge = await createDataJudProvider().observe(request(), {
      scenario: 'payload_too_large',
    });

    expect(invalidSchema).toMatchObject({
      kind: 'failure',
      status: 'technical_failure',
      errorCode: 'datajud_schema_invalid',
    });
    expect(mismatch).toMatchObject({
      kind: 'failure',
      status: 'technical_failure',
      errorCode: 'datajud_process_mismatch',
    });
    expect(tooLarge).toMatchObject({
      kind: 'failure',
      status: 'technical_failure',
      errorCode: 'datajud_payload_too_large',
    });
    expect(DATAJUD_MAX_RESPONSE_BYTES).toBeGreaterThan(0);
  });

  it('rejeita input com campos inesperados sem chamar o transporte', async () => {
    const transport = responseTransport({
      status: 200,
      body: { outcome: 'observation', processRef: 'synthetic-process-001' },
    });
    const result = await createDataJudProvider(transport).observe(request(), {
      scenario: 'success',
      unexpected: true,
    } as never);

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'technical_failure',
      errorCode: 'datajud_input_schema_invalid',
    });
    expect(transport.execute).not.toHaveBeenCalled();
  });

  it('passa timeout e correlação ao transporte e não envia segredo', async () => {
    const transport = responseTransport({
      status: 200,
      body: { outcome: 'observation', processRef: 'synthetic-process-001' },
    });
    const result = await createDataJudProvider(transport).observe(request(), {
      scenario: 'success',
    });
    const transportRequest = (transport.execute as ReturnType<typeof vi.fn>)
      .mock.calls[0]?.[0] as DataJudTransportRequest;

    expect(result.kind).toBe('observation');
    expect(transportRequest).toMatchObject({
      subjectRef: 'synthetic-process-001',
      correlationId: 'synthetic-datajud-correlation-001',
      timeoutMs: DATAJUD_TIMEOUT_MS,
    });
    expect(JSON.stringify(transportRequest)).not.toContain('APIKey');
    expect(JSON.stringify(result)).not.toContain('secret');
  });

  it('mantém a capability não declarada como not_supported pelo gateway', async () => {
    const gateway = createTestProviderGateway();
    const result = await gateway.observe(
      DATAJUD_PROVIDER_ID,
      request({ capability: 'documents' })
    );

    expect(result).toMatchObject({
      kind: 'failure',
      status: 'not_supported',
      errorCode: 'capability_not_supported',
      source: 'datajud',
    });
  });

  it('mantém fingerprint determinístico para o mesmo input sintético', () => {
    expect(
      providerFingerprint({
        provider: DATAJUD_PROVIDER_ID,
        processRef: 'synthetic-process-001',
        scenario: 'success',
      })
    ).toBe(
      providerFingerprint({
        scenario: 'success',
        processRef: 'synthetic-process-001',
        provider: DATAJUD_PROVIDER_ID,
      })
    );
  });
});

void createFakeDataJudTransport;
