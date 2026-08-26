import { describe, expect, it } from 'vitest';
import { getDataJudConfiguration } from '@/lib/providers/datajud-config-core';

describe('DataJud configuration', () => {
  it('usa fake por padrão sem exigir credencial', () => {
    const config = getDataJudConfiguration({});

    expect(config).toEqual({
      mode: 'fake',
      credentialState: 'absent',
      endpointConfigured: false,
    });
    expect(JSON.stringify(config)).not.toContain('secret');
  });

  it('não expõe o valor da credencial quando ela está presente', () => {
    const config = getDataJudConfiguration({
      DATAJUD_API_KEY: 'synthetic-secret-value',
    });

    expect(config).toMatchObject({
      mode: 'fake',
      credentialState: 'present',
    });
    expect(JSON.stringify(config)).not.toContain('synthetic-secret-value');
  });

  it('mantém o transporte real desabilitado mesmo com endpoint e credencial', () => {
    const config = getDataJudConfiguration({
      DATAJUD_TRANSPORT_MODE: 'real',
      DATAJUD_API_URL: 'https://example.invalid/datajud',
      DATAJUD_API_KEY: 'synthetic-secret-value',
    });

    expect(config).toMatchObject({
      mode: 'disabled',
      reason: 'real_transport_disabled',
      credentialState: 'present',
      endpointConfigured: true,
    });
  });

  it('desabilita endpoint inválido sem tentar interpretar credenciais', () => {
    const config = getDataJudConfiguration({
      DATAJUD_API_URL: 'not-an-url',
      DATAJUD_API_KEY: 'synthetic-secret-value',
    });

    expect(config).toMatchObject({
      mode: 'disabled',
      reason: 'invalid_endpoint',
      credentialState: 'present',
    });
  });
});
