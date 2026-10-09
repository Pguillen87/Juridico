import type { ClientPortfolioProcess } from '@/lib/clients/portfolio';
import { formatCnj } from '@/lib/processes/cnj';
import {
  formatNewsCount,
  formatSpreadsheetDate,
  formatSpreadsheetDateOnly,
  getMonitoringStateLabel,
  PORTFOLIO_SPREADSHEET_COLUMNS,
  type PortfolioSpreadsheetColumnKey,
} from './processes-spreadsheet-model';

export const PROCESS_EXPORT_COLUMN_KEYS = [
  'process',
  'client',
  'registrationStatus',
  'visibility',
  'monitoringState',
  'tribunal',
  'movementType',
  'movementDate',
  'description',
  'lastConsulted',
  'sourceUpdated',
  'newMovements',
] as const satisfies readonly PortfolioSpreadsheetColumnKey[];

export type ProcessExportColumnKey =
  (typeof PROCESS_EXPORT_COLUMN_KEYS)[number];

const exportableColumnKeys = new Set<string>(PROCESS_EXPORT_COLUMN_KEYS);
const columnLabels = new Map(
  PORTFOLIO_SPREADSHEET_COLUMNS.map((column) => [column.key, column.label])
);

function normalizeExportColumnKeys(
  visibleKeys: readonly string[]
): readonly ProcessExportColumnKey[] {
  return visibleKeys.filter((key): key is ProcessExportColumnKey =>
    exportableColumnKeys.has(key)
  );
}

export function getProcessExportHeaders(
  visibleKeys: readonly string[] = PROCESS_EXPORT_COLUMN_KEYS
) {
  return normalizeExportColumnKeys(visibleKeys).map(
    (key) => columnLabels.get(key) ?? key
  );
}

export const PROCESS_EXPORT_HEADERS = getProcessExportHeaders();

export type ProcessExportRow = {
  readonly selectionKey: string;
  readonly valuesByKey: Readonly<
    Partial<Record<PortfolioSpreadsheetColumnKey, string>>
  >;
  readonly values: readonly string[];
};

function escapeCsvCell(value: string) {
  return `"${value.replaceAll('"', '""')}"`;
}

export function buildProcessExportCsv(
  rows: readonly ProcessExportRow[],
  visibleKeys: readonly string[] = PROCESS_EXPORT_COLUMN_KEYS
) {
  const exportKeys = normalizeExportColumnKeys(visibleKeys);
  const lines = [
    getProcessExportHeaders(exportKeys),
    ...rows.map((row) => exportKeys.map((key) => row.valuesByKey[key] ?? '')),
  ].map((line) => line.map(escapeCsvCell).join(';'));
  return `\uFEFF${lines.join('\r\n')}\r\n`;
}

type ExportableProcess = {
  readonly cnj_number: string;
  readonly tribunal: string;
  readonly system: string | null;
  readonly is_public: boolean;
  readonly status: string;
};

export function buildProcessExportRow({
  process,
  index,
  clientName,
  portfolioProcess,
}: {
  readonly process: ExportableProcess;
  readonly index: number;
  readonly clientName: string;
  readonly portfolioProcess: ClientPortfolioProcess | undefined;
}): ProcessExportRow {
  void index;
  const state = portfolioProcess?.monitoringState ?? 'not_consulted';
  const movement = portfolioProcess?.lastMovement;
  const newMovementCount = portfolioProcess?.newMovementCount ?? 0;
  const valuesByKey: ProcessExportRow['valuesByKey'] = {
    process: formatCnj(process.cnj_number),
    client: clientName,
    registrationStatus: process.status === 'active' ? 'Ativo' : 'Inativo',
    visibility: process.is_public ? 'Público' : 'Sigiloso',
    monitoringState: getMonitoringStateLabel(state),
    tribunal: process.tribunal,
    system: process.system ?? portfolioProcess?.system ?? 'Não informado',
    processClass: portfolioProcess?.processClass ?? 'Ainda não informada',
    degree: portfolioProcess?.degree ?? 'Ainda não informado',
    court: portfolioProcess?.court ?? 'Não informado',
    sourceStatus: portfolioProcess?.sourceStatus ?? 'Não informado pela fonte',
    movementCode: movement?.code ?? 'Não informado',
    movementType: movement?.type ?? 'Não informado',
    movementDate: formatSpreadsheetDateOnly(
      movement?.date ?? null,
      'Não informado'
    ),
    description:
      movement?.description ?? 'Nenhum detalhe de andamento informado',
    movementCourt: movement?.court ?? 'Não informado',
    lastConsulted: formatSpreadsheetDate(
      portfolioProcess?.lastConsultedAt ?? null,
      'Não consultado'
    ),
    sourceUpdated: formatSpreadsheetDate(
      portfolioProcess?.sourceUpdatedAt ?? null,
      'Não informado'
    ),
    newMovements: formatNewsCount(
      newMovementCount,
      portfolioProcess?.hasNews ?? false,
      state
    ),
  };

  return {
    selectionKey: process.cnj_number,
    valuesByKey,
    values: PROCESS_EXPORT_COLUMN_KEYS.map((key) => valuesByKey[key] ?? ''),
  };
}
