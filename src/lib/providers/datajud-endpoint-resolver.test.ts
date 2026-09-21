import { describe, expect, it } from 'vitest';
import {
  resolveDataJudEndpoint,
  DATAJUD_DEFAULT_BASE_URL,
} from './datajud-endpoint-resolver';

describe('DataJud Endpoint Resolver', () => {
  it('resolve corretamente tribunal estadual TJSP (J=8, TR=26)', () => {
    const res = resolveDataJudEndpoint('0000001-73.2023.8.26.0100');
    expect(res).toEqual({
      supported: true,
      justice: '8',
      tribunalCode: '26',
      alias: 'tjsp',
      url: `${DATAJUD_DEFAULT_BASE_URL}/api_publica_tjsp/_search`,
    });
  });

  it('resolve corretamente tribunal federal TRF4 (J=4, TR=04)', () => {
    const res = resolveDataJudEndpoint('5000001-91.2023.4.04.7000');
    expect(res).toEqual({
      supported: true,
      justice: '4',
      tribunalCode: '04',
      alias: 'trf4',
      url: `${DATAJUD_DEFAULT_BASE_URL}/api_publica_trf4/_search`,
    });
  });

  it('resolve corretamente tribunal do trabalho TRT2 (J=5, TR=02)', () => {
    const res = resolveDataJudEndpoint('1000001-80.2023.5.02.0001');
    expect(res).toEqual({
      supported: true,
      justice: '5',
      tribunalCode: '02',
      alias: 'trt2',
      url: `${DATAJUD_DEFAULT_BASE_URL}/api_publica_trt2/_search`,
    });
  });

  it('retorna invalid_cnj_format para CNJs com formato ou dígitos verificadores inválidos', () => {
    const resShort = resolveDataJudEndpoint('12345');
    expect(resShort).toEqual({
      supported: false,
      reason: 'invalid_cnj_format',
    });

    const resBadChecksum = resolveDataJudEndpoint('0000001-00.2023.8.26.0100');
    expect(resBadChecksum).toEqual({
      supported: false,
      reason: 'invalid_cnj_format',
    });
  });

  it('retorna unsupported_tribunal para código de tribunal inexistente com CNJ matematicamente válido', () => {
    const res = resolveDataJudEndpoint('0000001-42.2023.8.99.0100');
    expect(res).toEqual({
      supported: false,
      reason: 'unsupported_tribunal',
    });
  });

  it('preserva o caminho do tribunal ao apontar para uma base HTTP local', () => {
    const res = resolveDataJudEndpoint(
      '0000001-73.2023.8.26.0100',
      'http://127.0.0.1:54322/'
    );

    expect(res).toMatchObject({
      supported: true,
      url: 'http://127.0.0.1:54322/api_publica_tjsp/_search',
    });
  });
});
