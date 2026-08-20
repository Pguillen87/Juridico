import { describe, it, expect, afterEach } from 'vitest';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { DataJudProvider } = require('./datajud_provider.js');
const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe('DataJudProvider - testes locais', () => {
  it('rejeita tribunalAlias não suportado', async () => {
    const result = await new DataJudProvider('dummy').query('00044531220268160000', 'api_publica_tjsp');
    expect(result.state).toBe('unsupported');
    expect(result.rawText).toBeNull();
  });

  it('normaliza resposta e preserva rawText exato', async () => {
    // String exata com formatação específica
    const exactRawText = '{ \n  "hits" : { \n    "hits" : [] \n  } \n}';

    globalThis.fetch = async () => ({
      ok: true,
      status: 200,
      text: async () => exactRawText
    });

    const result = await new DataJudProvider('dummy-test-key').query('00044531220268160000', 'api_publica_tjpr');
    expect(result.state).toBe('process_not_found');
    expect(result.rawText).toBe(exactRawText);
    expect(result.parsedPayload).toEqual({ hits: { hits: [] } });
  });

  it('normaliza resposta e extrai _source separadamente', async () => {
    const fakeRaw = {
      hits: {
        hits: [{
          _source: {
            numeroProcesso: '00044531220268160000',
            classe: { nome: 'Teste' },
            assuntos: [{ nome: 'Assunto' }],
            movimentos: [{ codigo: 1, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.000Z' }]
          }
        }]
      }
    };

    globalThis.fetch = async () => ({
      ok: true,
      status: 200,
      text: async () => JSON.stringify(fakeRaw)
    });

    const result = await new DataJudProvider('dummy-test-key').query('00044531220268160000', 'api_publica_tjpr');
    expect(result.state).toBe('success_without_changes');
    expect(result.rawText).toBe(JSON.stringify(fakeRaw));
    expect(result.parsedPayload).toEqual(fakeRaw);
    expect(result.normalizedData.movements).toHaveLength(1);
    expect(result.capabilitiesProvided).toEqual(['basic_data', 'movements']);
  });

  it('mapeia resposta vazia para process_not_found', async () => {
    globalThis.fetch = async () => ({ ok: true, status: 200, text: async () => JSON.stringify({ hits: { hits: [] } }) });
    const result = await new DataJudProvider('dummy-test-key').query('00044531220268160000', 'api_publica_tjpr');
    expect(result.state).toBe('process_not_found');
  });

  it('mapeia HTTP 429 para rate_limited', async () => {
    globalThis.fetch = async () => ({ ok: false, status: 429, statusText: 'Too Many Requests' });
    const result = await new DataJudProvider('dummy-test-key').query('00044531220268160000', 'api_publica_tjpr');
    expect(result.state).toBe('rate_limited');
  });

  it('mapeia HTTP 500/503 para source_unavailable', async () => {
    for (const status of [500, 503]) {
      globalThis.fetch = async () => ({ ok: false, status, statusText: 'Service Unavailable' });
      const result = await new DataJudProvider('dummy-test-key').query('00044531220268160000', 'api_publica_tjpr');
      expect(result.state).toBe('source_unavailable');
    }
  });

  it('mapeia JSON inválido para failed e timeout para timeout', async () => {
    globalThis.fetch = async () => ({ ok: true, status: 200, text: async () => 'not a json' });
    const invalidJson = await new DataJudProvider('dummy-test-key').query('00044531220268160000', 'api_publica_tjpr');
    expect(invalidJson.state).toBe('failed');
    expect(invalidJson.rawText).toBe('not a json');

    globalThis.fetch = async () => { throw new DOMException('timeout', 'TimeoutError'); };
    const timeout = await new DataJudProvider('dummy-test-key').query('00044531220268160000', 'api_publica_tjpr');
    expect(timeout.state).toBe('timeout');
  });
});
