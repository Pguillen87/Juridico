import { describe, expect, it } from 'vitest';
import {
  PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS,
  PORTFOLIO_SPREADSHEET_COLUMNS,
  formatNewsCount,
  formatSpreadsheetDate,
  getMonitoringStateLabel,
  getPortfolioStateMessage,
} from './processes-spreadsheet-model';

describe('processes spreadsheet model', () => {
  it('defines comparable process information as individual column headers', () => {
    expect(PORTFOLIO_SPREADSHEET_COLUMNS.map((column) => column.label)).toEqual(
      [
        'Selecionar',
        'Processo',
        'Cliente',
        'Status do cadastro',
        'Visibilidade',
        'Estado da consulta',
        'Tribunal',
        'Sistema',
        'Classe',
        'Grau',
        'Órgão julgador',
        'Situação da fonte',
        'Código do andamento',
        'Tipo do andamento',
        'Data do andamento',
        'Descrição do andamento',
        'Órgão do andamento',
        'Última consulta',
        'Atualização da fonte',
        'Novas movimentações',
        'Ações',
      ]
    );
  });

  it('opens only the operational columns by default', () => {
    expect(PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS).toEqual([
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
    ]);
    expect(PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS).not.toContain('sourceStatus');
    expect(PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS).not.toContain('movementCode');
  });

  it('does not combine consultation state with its explanatory message', () => {
    expect(
      PORTFOLIO_SPREADSHEET_COLUMNS.map((column) => column.label)
    ).not.toContain('Mensagem da consulta');
    expect(
      PORTFOLIO_SPREADSHEET_COLUMNS.map((column) => column.label)
    ).toContain('Estado da consulta');
    expect(
      PORTFOLIO_SPREADSHEET_COLUMNS.map((column) => column.label)
    ).toContain('Descrição do andamento');
  });

  it('keeps technical monitoring states translated for the lawyer', () => {
    expect(getMonitoringStateLabel('changed')).toBe('Com novidades');
    expect(getMonitoringStateLabel('manual_review')).toBe('Revisão necessária');
    expect(
      getPortfolioStateMessage({
        state: 'changed',
        newMovementCount: 2,
      })
    ).toBe('2 novas movimentações desde a última consulta.');
    expect(
      getPortfolioStateMessage({
        state: 'first_observation',
        newMovementCount: 1,
      })
    ).toBe('Primeira consulta concluída — 1 movimentação disponível.');
  });

  it('makes missing dates explicit instead of showing an invalid date', () => {
    expect(formatSpreadsheetDate(null)).toBe('Não informado');
    expect(formatSpreadsheetDate(null, 'Não consultado')).toBe(
      'Não consultado'
    );
    expect(formatSpreadsheetDate('2026-09-20T12:00:00.000Z')).toMatch(
      /20\/09\/2026/
    );
  });

  it('keeps the movement count independent from the consultation message', () => {
    expect(formatNewsCount(2, true, 'changed')).toBe('2');
    expect(formatNewsCount(1, false, 'first_observation')).toBe('1');
    expect(formatNewsCount(0, false, 'unchanged')).toBe('0');
    expect(formatNewsCount(0, false, 'failure')).toBe('—');
    expect(formatNewsCount(0, false, 'not_consulted')).toBe('—');
  });
});
