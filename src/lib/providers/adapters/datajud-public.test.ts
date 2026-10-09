import { describe, expect, it } from 'vitest';
import {
  DataJudPublicAdapter,
  DATAJUD_PUBLIC_PROVIDER_ID,
} from './datajud-public';
import {
  type DataJudTransport,
  type DataJudTransportResult,
} from './datajud-core';
import { DataJudHttpTransport } from './datajud-http-transport';
import { type ProviderRequestV1 } from '../contract';

function makeRequest(cnj = '0000001-23.2023.8.26.0100'): ProviderRequestV1 {
  return {
    contractVersion: 1,
    operation: 'observe_process',
    capability: 'process_observation',
    subjectRef: { type: 'process', value: cnj },
    requestFingerprint: 'a'.repeat(64),
    correlationId: 'req-12345',
    requestedAt: '2026-09-05T12:00:00.000Z',
    executionContext: {
      kind: 'system',
      actorUserId: null,
      officeId: '00000000-0000-0000-0000-000000000001',
      role: null,
      isOwner: false,
      workerId: 'worker-1',
    },
  };
}

class MockTransport implements DataJudTransport {
  constructor(private readonly result: DataJudTransportResult) {}
  async execute(): Promise<DataJudTransportResult> {
    return this.result;
  }
}

describe('DataJud Public Adapter', () => {
  it('transporte HTTP sem credencial retorna not_configured sem chamar a rede', async () => {
    let called = false;
    const transport = new DataJudHttpTransport({
      fetchFn: async () => {
        called = true;
        throw new Error('rede não deveria ser chamada');
      },
    });

    const result = await transport.execute({
      subjectRef: makeRequest().subjectRef.value,
      correlationId: 'transport-test',
      requestedAt: '2026-09-05T12:00:00.000Z',
      timeoutMs: 100,
    });

    expect(result).toEqual({
      kind: 'transport_failure',
      code: 'not_configured',
    });
    expect(called).toBe(false);
  });

  it('usa base URL local somente como destino do transporte HTTP real', async () => {
    let calledUrl = '';
    let calledHeaders: HeadersInit | undefined;
    const transport = new DataJudHttpTransport({
      apiKey: 'TestOnly-Local-123!',
      endpointBaseUrl: 'http://127.0.0.1:54322/',
      fetchFn: async (input, init) => {
        calledUrl = String(input);
        calledHeaders = init?.headers;
        return new Response(
          JSON.stringify({ hits: { total: { value: 0 }, hits: [] } }),
          {
            status: 200,
            headers: { 'content-type': 'application/json' },
          }
        );
      },
    });

    const result = await transport.execute({
      subjectRef: '0000001-73.2023.8.26.0100',
      correlationId: 'test-correlation',
      requestedAt: new Date().toISOString(),
      timeoutMs: 100,
    });

    expect(result).toMatchObject({ status: 200 });
    expect(calledUrl).toBe('http://127.0.0.1:54322/api_publica_tjsp/_search');
    expect(calledHeaders).toMatchObject({
      Authorization: 'APIKey TestOnly-Local-123!',
      'X-Correlation-Id': 'test-correlation',
    });
  });

  it('não fabrica sucesso quando o transporte não está configurado', async () => {
    const adapter = new DataJudPublicAdapter(
      new MockTransport({ kind: 'transport_failure', code: 'not_configured' })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());

    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('technical_failure');
    expect(result.errorCode).toBe('datajud_not_configured');
  });

  it('normaliza com sucesso resposta válida do Elasticsearch com movimentos e sourceUpdatedAt', async () => {
    const rawEs = {
      hits: {
        total: { value: 1 },
        hits: [
          {
            _source: {
              numeroProcesso: '00000012320238260100',
              siglaTribunal: 'TJSP',
              dataAjuizamento: '2026-01-10',
              grau: 'G1',
              nivelSigilo: 0,
              formato: { codigo: 1, nome: 'Eletrônico' },
              sistema: { codigo: 1, nome: 'PJe' },
              classe: { codigo: 1116, nome: 'Ação de cobrança' },
              assuntos: [{ codigo: 1234, nome: 'Obrigações' }],
              orgaoJulgador: {
                codigo: 100,
                nome: '1ª Vara Cível',
              },
              dataHoraUltimaAtualizacao: '2026-09-01T15:30:00.000Z',
              movimentos: [
                {
                  codigo: 60,
                  nome: 'Expedição de Termo',
                  dataHora: '2026-08-30T10:00:00.000Z',
                  orgaoJulgador: {
                    codigoOrgao: 100,
                    nomeOrgao: '1ª Vara Cível',
                  },
                },
              ],
            },
          },
        ],
      },
    };

    const adapter = new DataJudPublicAdapter(
      new MockTransport({ status: 200, body: rawEs })
    );

    const { result, rawPayload } =
      await adapter.observeWithPayload(makeRequest());

    expect(result.kind).toBe('observation');
    if (result.kind !== 'observation') return;

    expect(result.status).toBe('observed');
    expect(result.provider.providerId).toBe(DATAJUD_PUBLIC_PROVIDER_ID);
    expect(result.data.tribunal).toBe('TJSP');
    expect(result.data.basicData).toEqual({
      filingDate: '2026-01-10T00:00:00.000Z',
      degree: 'G1',
      secrecyLevel: '0',
      format: { code: '1', name: 'Eletrônico' },
      system: { code: '1', name: 'PJe' },
      processClass: { code: '1116', name: 'Ação de cobrança' },
      subjects: [{ code: '1234', name: 'Obrigações' }],
      court: { code: '100', name: '1ª Vara Cível' },
    });
    expect(result.data.movements).toHaveLength(1);
    expect(result.data.movements?.[0]).toMatchObject({
      code: '60',
      type: 'Expedição de Termo',
      court: { code: '100', name: '1ª Vara Cível' },
    });
    expect(result.data.movements?.[0].description).toBe('Expedição de Termo');
    expect(result.missingFields).toEqual(['parties']);
    expect(result.sourceMetadata.sourceUpdatedAt).toBe(
      '2026-09-01T15:30:00.000Z'
    );
    expect(result.evidence?.evidenceType).toBe('provider_response');
    expect(rawPayload).toEqual(rawEs);
  });

  it('deduplica movimentos estritamente idênticos', async () => {
    const rawEs = {
      hits: {
        total: 1,
        hits: [
          {
            _source: {
              numeroProcesso: '00000012320238260100',
              siglaTribunal: 'TJSP',
              movimentos: [
                {
                  codigo: 60,
                  nome: 'Juntada de Petição',
                  dataHora: '2026-08-30T10:00:00.000Z',
                  orgaoJulgador: { codigoOrgao: 100 },
                },
                {
                  codigo: 60,
                  nome: 'Juntada de Petição',
                  dataHora: '2026-08-30T10:00:00.000Z',
                  orgaoJulgador: { codigoOrgao: 100 },
                },
              ],
            },
          },
        ],
      },
    };

    const adapter = new DataJudPublicAdapter(
      new MockTransport({ status: 200, body: rawEs })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('observation');
    if (result.kind !== 'observation') return;
    expect(result.data.movements).toHaveLength(1);
  });

  it('detecta colisão ambígua de movimentos com mesma chave mas conteúdos divergentes', async () => {
    const rawEs = {
      hits: {
        total: 1,
        hits: [
          {
            _source: {
              numeroProcesso: '00000012320238260100',
              siglaTribunal: 'TJSP',
              movimentos: [
                {
                  codigo: 60,
                  nome: 'Despacho A',
                  dataHora: '2026-08-30T10:00:00.000Z',
                  orgaoJulgador: { codigoOrgao: 100 },
                },
                {
                  codigo: 60,
                  nome: 'Despacho B (Diferente)',
                  dataHora: '2026-08-30T10:00:00.000Z',
                  orgaoJulgador: { codigoOrgao: 100 },
                },
              ],
            },
          },
        ],
      },
    };

    const adapter = new DataJudPublicAdapter(
      new MockTransport({ status: 200, body: rawEs })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('manual_review_required');
    expect(result.errorCode).toBe('datajud_movement_ambiguity_detected');
  });

  it('retorna not_found para resultado com total hits 0', async () => {
    const rawEs = {
      hits: {
        total: { value: 0 },
        hits: [],
      },
    };

    const adapter = new DataJudPublicAdapter(
      new MockTransport({ status: 200, body: rawEs })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('not_found');
    expect(result.errorCode).toBe('datajud_not_found');
  });

  it('trata status 401/403 como falha técnica de autenticação', async () => {
    const adapter = new DataJudPublicAdapter(
      new MockTransport({ status: 401, body: { error: 'Unauthorized' } })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('technical_failure');
    expect(result.errorCode).toBe('datajud_auth_failure');
  });

  it('trata falha de timeout do transporte HTTP', async () => {
    const adapter = new DataJudPublicAdapter(
      new MockTransport({ kind: 'transport_failure', code: 'timeout' })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('timeout');
    expect(result.errorCode).toBe('datajud_timeout');
  });

  it('retorna manual_review_required quando múltiplos hits são retornados pelo DataJud', async () => {
    const rawEs = {
      hits: {
        total: 2,
        hits: [
          {
            _source: {
              numeroProcesso: '00000012320238260100',
              siglaTribunal: 'TJSP',
            },
          },
          {
            _source: {
              numeroProcesso: '00000012320238260100',
              siglaTribunal: 'TJSP',
            },
          },
        ],
      },
    };

    const adapter = new DataJudPublicAdapter(
      new MockTransport({ status: 200, body: rawEs })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('manual_review_required');
    expect(result.errorCode).toBe('datajud_multiple_hits_returned');
  });

  it('trata status HTTP 404 como falha técnica de endpoint não suportado', async () => {
    const adapter = new DataJudPublicAdapter(
      new MockTransport({ status: 404, body: { error: 'Not Found' } })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('technical_failure');
    expect(result.errorCode).toBe('datajud_endpoint_not_supported');
  });

  it('captura Retry-After real do header para status 429', async () => {
    const adapter = new DataJudPublicAdapter(
      new MockTransport({
        status: 429,
        body: { error: 'Rate limit exceeded' },
        headers: { 'retry-after': '45' },
      })
    );

    const { result } = await adapter.observeWithPayload(makeRequest());
    expect(result.kind).toBe('failure');
    if (result.kind !== 'failure') return;
    expect(result.status).toBe('rate_limited');
    expect(result.errorCode).toBe('datajud_rate_limited');
    expect(result.retryAfterMs).toBe(45_000);
  });
});
