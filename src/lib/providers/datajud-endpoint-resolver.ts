import { validateCnj } from '@/lib/processes/cnj';

export const DATAJUD_CANONICAL_HOST = 'api-publica.datajud.cnj.jus.br';
export const DATAJUD_DEFAULT_BASE_URL = `https://${DATAJUD_CANONICAL_HOST}`;

export type DataJudEndpointResolution =
  | {
      readonly supported: true;
      readonly justice: string;
      readonly tribunalCode: string;
      readonly alias: string;
      readonly url: string;
    }
  | {
      readonly supported: false;
      readonly reason: 'invalid_cnj_format' | 'unsupported_tribunal';
    };

const ESTADUAL_MAP: Record<string, string> = {
  '01': 'tjac',
  '02': 'tjal',
  '03': 'tjap',
  '04': 'tjam',
  '05': 'tjba',
  '06': 'tjce',
  '07': 'tjdft',
  '08': 'tjes',
  '09': 'tjgo',
  '10': 'tjma',
  '11': 'tjmt',
  '12': 'tjms',
  '13': 'tjmg',
  '14': 'tjpa',
  '15': 'tjpb',
  '16': 'tjpr',
  '17': 'tjpe',
  '18': 'tjpi',
  '19': 'tjrj',
  '20': 'tjrn',
  '21': 'tjrs',
  '22': 'tjro',
  '23': 'tjrr',
  '24': 'tjsc',
  '25': 'tjse',
  '26': 'tjsp',
  '27': 'tjto',
};

const FEDERAL_MAP: Record<string, string> = {
  '01': 'trf1',
  '02': 'trf2',
  '03': 'trf3',
  '04': 'trf4',
  '05': 'trf5',
  '06': 'trf6',
};

const TRABALHO_MAP: Record<string, string> = {
  '01': 'trt1',
  '02': 'trt2',
  '03': 'trt3',
  '04': 'trt4',
  '05': 'trt5',
  '06': 'trt6',
  '07': 'trt7',
  '08': 'trt8',
  '09': 'trt9',
  '10': 'trt10',
  '11': 'trt11',
  '12': 'trt12',
  '13': 'trt13',
  '14': 'trt14',
  '15': 'trt15',
  '16': 'trt16',
  '17': 'trt17',
  '18': 'trt18',
  '19': 'trt19',
  '20': 'trt20',
  '21': 'trt21',
  '22': 'trt22',
  '23': 'trt23',
  '24': 'trt24',
};

const SUPERIOR_MAP: Record<string, string> = {
  '1': 'stf',
  '2': 'cnj',
  '3': 'stj',
  '4': 'stm',
  '5': 'tst',
  '6': 'tse',
};

export function resolveDataJudEndpoint(
  cnjNumber: string,
  baseUrl = DATAJUD_DEFAULT_BASE_URL
): DataJudEndpointResolution {
  const validation = validateCnj(cnjNumber);
  if (!validation.valid || !validation.normalized) {
    return { supported: false, reason: 'invalid_cnj_format' };
  }

  const digits = validation.normalized;
  const justice = digits.slice(13, 14);
  const tribunalCode = digits.slice(14, 16);

  let alias: string | undefined;

  if (justice === '8') {
    alias = ESTADUAL_MAP[tribunalCode];
  } else if (justice === '4') {
    alias = FEDERAL_MAP[tribunalCode];
  } else if (justice === '5') {
    alias = TRABALHO_MAP[tribunalCode];
  } else if (justice === '9') {
    if (tribunalCode === '13') alias = 'tjmmg';
    else if (tribunalCode === '21') alias = 'tjmrs';
    else if (tribunalCode === '25') alias = 'tjmsp';
  } else {
    alias = SUPERIOR_MAP[justice];
  }

  if (!alias) {
    return { supported: false, reason: 'unsupported_tribunal' };
  }

  const normalizedBaseUrl = baseUrl.replace(/\/+$/, '');
  const url = `${normalizedBaseUrl}/api_publica_${alias}/_search`;

  return {
    supported: true,
    justice,
    tribunalCode,
    alias,
    url,
  };
}
