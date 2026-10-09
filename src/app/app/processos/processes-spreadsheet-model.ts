import type { ClientPortfolioProcessState } from '@/lib/clients/portfolio';

export const PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS = [
  'select',
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
  'actions',
] as const;

export const PORTFOLIO_SPREADSHEET_COLUMNS = [
  { key: 'select', label: 'Selecionar', width: 'w-[92px]' },
  { key: 'process', label: 'Processo', width: 'w-[220px]' },
  { key: 'client', label: 'Cliente', width: 'w-[190px]' },
  {
    key: 'registrationStatus',
    label: 'Status do cadastro',
    width: 'w-[145px]',
  },
  { key: 'visibility', label: 'Visibilidade', width: 'w-[125px]' },
  { key: 'monitoringState', label: 'Estado da consulta', width: 'w-[180px]' },
  { key: 'tribunal', label: 'Tribunal', width: 'w-[130px]' },
  { key: 'system', label: 'Sistema', width: 'w-[120px]' },
  { key: 'processClass', label: 'Classe', width: 'w-[220px]' },
  { key: 'degree', label: 'Grau', width: 'w-[100px]' },
  { key: 'court', label: 'Órgão julgador', width: 'w-[220px]' },
  { key: 'sourceStatus', label: 'Situação da fonte', width: 'w-[210px]' },
  { key: 'movementCode', label: 'Código do andamento', width: 'w-[180px]' },
  { key: 'movementType', label: 'Tipo do andamento', width: 'w-[220px]' },
  { key: 'movementDate', label: 'Data do andamento', width: 'w-[145px]' },
  {
    key: 'description',
    label: 'Descrição do andamento',
    width: 'w-[340px]',
  },
  { key: 'movementCourt', label: 'Órgão do andamento', width: 'w-[220px]' },
  { key: 'lastConsulted', label: 'Última consulta', width: 'w-[155px]' },
  {
    key: 'sourceUpdated',
    label: 'Atualização da fonte',
    width: 'w-[170px]',
  },
  { key: 'newMovements', label: 'Novas movimentações', width: 'w-[170px]' },
  { key: 'actions', label: 'Ações', width: 'w-[210px]' },
] as const;

export type PortfolioSpreadsheetColumnKey =
  (typeof PORTFOLIO_SPREADSHEET_COLUMNS)[number]['key'];

export type PortfolioSpreadsheetColumn =
  (typeof PORTFOLIO_SPREADSHEET_COLUMNS)[number];

const defaultVisibleColumns = new Set<string>(
  PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS
);

export function isPortfolioColumnVisibleByDefault(
  key: PortfolioSpreadsheetColumnKey
) {
  return defaultVisibleColumns.has(key);
}

export function getPortfolioSpreadsheetColumns(
  visibleKeys: readonly string[] = PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS
): readonly PortfolioSpreadsheetColumn[] {
  const visible = new Set(visibleKeys);
  return PORTFOLIO_SPREADSHEET_COLUMNS.filter((column) =>
    visible.has(column.key)
  );
}

export function getMonitoringStateLabel(
  state: ClientPortfolioProcessState
): string {
  switch (state) {
    case 'not_consulted':
      return 'Ainda não consultado';
    case 'updating':
      return 'Atualizando';
    case 'first_observation':
      return 'Primeira consulta';
    case 'unchanged':
      return 'Sem novidade';
    case 'changed':
      return 'Com novidades';
    case 'failure':
      return 'Falha na consulta';
    case 'manual_review':
      return 'Revisão necessária';
  }
}

export function getPortfolioStateMessage({
  state,
  newMovementCount,
}: {
  state: ClientPortfolioProcessState;
  newMovementCount: number;
}): string {
  switch (state) {
    case 'updating':
      return 'Atualizando processo...';
    case 'first_observation':
      return newMovementCount === 1
        ? 'Primeira consulta concluída — 1 movimentação disponível.'
        : `Primeira consulta concluída — ${newMovementCount} movimentações disponíveis.`;
    case 'changed':
      return newMovementCount === 1
        ? '1 nova movimentação desde a última consulta.'
        : `${newMovementCount} novas movimentações desde a última consulta.`;
    case 'failure':
      return 'Não foi possível concluir a consulta.';
    case 'manual_review':
      return 'Encontramos uma inconsistência nos dados da fonte. É necessária revisão.';
    case 'unchanged':
      return 'Sem novas movimentações desde a última consulta.';
    case 'not_consulted':
      return 'Este processo ainda não foi atualizado.';
  }
}

export function formatSpreadsheetDate(
  value: string | null,
  emptyLabel = 'Não informado'
): string {
  return value ? new Date(value).toLocaleString('pt-BR') : emptyLabel;
}

export function formatSpreadsheetDateOnly(
  value: string | null,
  emptyLabel = 'Não informado'
): string {
  return value ? new Date(value).toLocaleDateString('pt-BR') : emptyLabel;
}

export function formatNewsCount(
  count: number,
  hasNews: boolean,
  state: ClientPortfolioProcessState
): string {
  if (
    state === 'failure' ||
    state === 'manual_review' ||
    state === 'updating' ||
    state === 'not_consulted'
  ) {
    return '—';
  }
  if (state === 'first_observation') return String(count);
  if (state === 'unchanged' || !hasNews) return '0';
  return String(count);
}
