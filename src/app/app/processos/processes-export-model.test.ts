import { describe, expect, it } from 'vitest';
import {
  buildProcessExportCsv,
  buildProcessExportRow,
  getProcessExportHeaders,
  PROCESS_EXPORT_HEADERS,
} from './processes-export-model';

describe('processes export model', () => {
  it('keeps the export focused on the visible legal portfolio fields', () => {
    const row = buildProcessExportRow({
      process: {
        cnj_number: '00044531220268160000',
        tribunal: 'TJPR',
        system: 'PJe',
        is_public: true,
        status: 'active',
      },
      index: 0,
      clientName: 'Cliente Teste',
      portfolioProcess: undefined,
    });

    expect(PROCESS_EXPORT_HEADERS).toEqual([
      'Processo',
      'Cliente',
      'Status do cadastro',
      'Visibilidade',
      'Estado da consulta',
      'Tribunal',
      'Tipo do andamento',
      'Data do andamento',
      'Descrição do andamento',
      'Última consulta',
      'Atualização da fonte',
      'Novas movimentações',
    ]);
    expect(getProcessExportHeaders(['process', 'description'])).toEqual([
      'Processo',
      'Descrição do andamento',
    ]);
    expect(PROCESS_EXPORT_HEADERS).not.toContain('UUID');
    expect(row.selectionKey).toBe('00044531220268160000');
    expect(row.values).toEqual([
      '0004453-12.2026.8.16.0000',
      'Cliente Teste',
      'Ativo',
      'Público',
      'Ainda não consultado',
      'TJPR',
      'Não informado',
      'Não informado',
      'Nenhum detalhe de andamento informado',
      'Não consultado',
      'Não informado',
      '—',
    ]);

    const csv = buildProcessExportCsv([row]);
    expect(csv.startsWith('\uFEFF')).toBe(true);
    expect(csv).toContain('"Processo"');
    expect(csv).toContain('"0004453-12.2026.8.16.0000"');
    expect(csv).toContain(';"Descrição do andamento";');
  });

  it('exports only the selected columns when the grid is narrowed', () => {
    const row = buildProcessExportRow({
      process: {
        cnj_number: '00044531220268160000',
        tribunal: 'TJPR',
        system: 'PJe',
        is_public: true,
        status: 'active',
      },
      index: 0,
      clientName: 'Cliente Teste',
      portfolioProcess: undefined,
    });

    const csv = buildProcessExportCsv([row], ['process', 'description']);
    expect(csv).toContain('"Processo";"Descrição do andamento"');
    expect(csv).not.toContain('"Cliente"');
  });
});
