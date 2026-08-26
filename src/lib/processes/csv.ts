import { createHash } from 'node:crypto';
import { normalizeCnj } from './cnj';

export const CSV_PARSER_VERSION = 'phase6-csv-v1';
export const MAX_CSV_BYTES = 2 * 1024 * 1024;
export const MAX_CSV_ROWS = 1000;

export type ParsedCsvRow = {
  line: number;
  cnj: string;
  clientName: string;
  tribunal: string;
  system: string | null;
  partyName: string | null;
  role: string | null;
  isPublic: boolean;
  monitoringStatus: 'paused';
  notes: string | null;
};

export type CsvRowError = {
  line: number;
  message: string;
};

export type ParsedCsv = {
  contentHash: string;
  headers: string[];
  rows: ParsedCsvRow[];
  errors: CsvRowError[];
  warnings: CsvRowError[];
  empty: boolean;
};

const HEADER_ALIASES: Record<string, string> = {
  cnj: 'cnj',
  'numero cnj': 'cnj',
  'número cnj': 'cnj',
  cliente: 'cliente',
  client: 'cliente',
  tribunal: 'tribunal',
  sistema: 'sistema',
  system: 'sistema',
  parte: 'parte',
  party: 'parte',
  relacao: 'papel',
  papel: 'papel',
  role: 'papel',
  'publico/sigiloso': 'publicidade',
  publicidade: 'publicidade',
  public: 'publicidade',
  monitoramento: 'monitoramento',
  monitoring: 'monitoramento',
  observacoes: 'observacoes',
  notes: 'observacoes',
};

const REQUIRED_HEADERS = ['cnj', 'cliente', 'tribunal'];
const ALLOWED_HEADERS = new Set([
  'cnj',
  'cliente',
  'tribunal',
  'sistema',
  'parte',
  'papel',
  'publicidade',
  'monitoramento',
  'observacoes',
]);

function normalizeHeader(value: string) {
  return value
    .replace(/^\uFEFF/, '')
    .trim()
    .toLocaleLowerCase('pt-BR')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

function parseCsvRecords(input: string): string[][] {
  const records: string[][] = [];
  let record: string[] = [];
  let field = '';
  let quoted = false;

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    if (quoted) {
      if (char === '"') {
        if (input[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          quoted = false;
        }
      } else {
        field += char;
      }
      continue;
    }
    if (char === '"' && field.length === 0) {
      quoted = true;
    } else if (char === ',') {
      record.push(field);
      field = '';
    } else if (char === '\n' || char === '\r') {
      if (char === '\r' && input[index + 1] === '\n') index += 1;
      record.push(field);
      field = '';
      if (record.some((cell) => cell.trim() !== '')) records.push(record);
      record = [];
    } else {
      field += char;
    }
  }

  if (quoted) throw new Error('CSV inválido: campo quoted não foi encerrado.');
  if (field.length > 0 || record.length > 0) {
    record.push(field);
    if (record.some((cell) => cell.trim() !== '')) records.push(record);
  }
  return records;
}

function parsePublicity(value: string, line: number): boolean {
  const normalized = value.trim().toLocaleLowerCase('pt-BR');
  if (
    !normalized ||
    ['público', 'publico', 'public', 'true', 'sim', 'yes', '1'].includes(
      normalized
    )
  )
    return true;
  if (
    [
      'sigiloso',
      'privado',
      'private',
      'false',
      'não',
      'nao',
      'no',
      '0',
    ].includes(normalized)
  )
    return false;
  throw new Error(`Linha ${line}: publicidade deve ser público ou sigiloso.`);
}

function normalizeRole(value: string): string | null {
  const role = value.trim().toLocaleLowerCase('pt-BR');
  return role || null;
}

export async function parseCsvFile(file: File): Promise<ParsedCsv> {
  if (file.size > MAX_CSV_BYTES) {
    throw new Error(`CSV excede o limite de ${MAX_CSV_BYTES} bytes.`);
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  const content = new TextDecoder('utf-8', { fatal: true })
    .decode(bytes)
    .replace(/^\uFEFF/, '');
  const contentHash = createHash('sha256').update(bytes).digest('hex');
  if (!content.trim()) {
    return {
      contentHash,
      headers: [],
      rows: [],
      errors: [],
      warnings: [],
      empty: true,
    };
  }

  const records = parseCsvRecords(content);
  if (records.length === 0) {
    return {
      contentHash,
      headers: [],
      rows: [],
      errors: [],
      warnings: [],
      empty: true,
    };
  }
  const rawHeaders = records[0].map(normalizeHeader);
  const headers = rawHeaders.map((header) => HEADER_ALIASES[header] ?? header);
  const errors: CsvRowError[] = [];
  const warnings: CsvRowError[] = [];
  const duplicateHeaders = headers.filter(
    (header, index) => headers.indexOf(header) !== index
  );
  if (duplicateHeaders.length > 0) {
    errors.push({
      line: 1,
      message: `Cabeçalho duplicado: ${duplicateHeaders[0]}.`,
    });
  }
  for (const required of REQUIRED_HEADERS) {
    if (!headers.includes(required))
      errors.push({
        line: 1,
        message: `Coluna obrigatória ausente: ${required}.`,
      });
  }
  const unknown = headers.filter((header) => !ALLOWED_HEADERS.has(header));
  for (const header of unknown)
    errors.push({ line: 1, message: `Coluna desconhecida: ${header}.` });

  const rows: ParsedCsvRow[] = [];
  const seenCnj = new Set<string>();
  if (records.length - 1 > MAX_CSV_ROWS) {
    errors.push({
      line: 1,
      message: `CSV excede o máximo de ${MAX_CSV_ROWS} linhas.`,
    });
  }

  records.slice(1, MAX_CSV_ROWS + 1).forEach((record, index) => {
    const line = index + 2;
    const values = new Map(
      headers.map((header, headerIndex) => [
        header,
        (record[headerIndex] ?? '').trim(),
      ])
    );
    if (record.every((cell) => cell.trim() === '')) {
      warnings.push({ line, message: 'Linha vazia ignorada na prévia.' });
      return;
    }
    try {
      const cnj = normalizeCnj(values.get('cnj') ?? '');
      if (seenCnj.has(cnj))
        throw new Error(`Linha ${line}: CNJ duplicado no arquivo.`);
      seenCnj.add(cnj);
      const clientName = values.get('cliente') ?? '';
      const tribunal = values.get('tribunal') ?? '';
      const system = values.get('sistema') || null;
      const partyName = values.get('parte') || null;
      const role = normalizeRole(values.get('papel') ?? '');
      const publicity = values.get('publicidade') ?? '';
      const monitoring = (values.get('monitoramento') ?? '').toLocaleLowerCase(
        'pt-BR'
      );
      const notes = values.get('observacoes') || null;
      if (clientName.length < 2)
        throw new Error(`Linha ${line}: cliente é obrigatório.`);
      if (tribunal.length < 2 || tribunal.length > 200)
        throw new Error(`Linha ${line}: tribunal inválido.`);
      if (system && system.length > 120)
        throw new Error(`Linha ${line}: sistema excede 120 caracteres.`);
      if (partyName && !role)
        throw new Error(
          `Linha ${line}: papel é obrigatório quando parte é informada.`
        );
      if (
        role &&
        ![
          'client',
          'plaintiff',
          'defendant',
          'representative',
          'interested_party',
          'other',
        ].includes(role)
      ) {
        throw new Error(`Linha ${line}: papel de processo inválido.`);
      }
      if (notes && notes.length > 1000)
        throw new Error(`Linha ${line}: observações excedem 1000 caracteres.`);
      const isPublic = parsePublicity(publicity, line);
      if (monitoring && monitoring !== 'paused' && monitoring !== 'pausado') {
        throw new Error(
          `Linha ${line}: monitoramento deve permanecer pausado nesta fase.`
        );
      }
      rows.push({
        line,
        cnj,
        clientName,
        tribunal,
        system,
        partyName,
        role,
        isPublic,
        monitoringStatus: 'paused',
        notes,
      });
    } catch (error) {
      errors.push({
        line,
        message:
          error instanceof Error
            ? error.message
            : `Linha ${line}: dados inválidos.`,
      });
      rows.push({
        line,
        cnj: values.get('cnj') ?? '',
        clientName: values.get('cliente') ?? '',
        tribunal: values.get('tribunal') ?? '',
        system: values.get('sistema') || null,
        partyName: values.get('parte') || null,
        role: normalizeRole(values.get('papel') ?? ''),
        isPublic: true,
        monitoringStatus: 'paused',
        notes: values.get('observacoes') || null,
      });
    }
  });

  return { contentHash, headers, rows, errors, warnings, empty: false };
}
