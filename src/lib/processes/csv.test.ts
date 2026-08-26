import { describe, expect, it } from 'vitest';
import { parseCsvFile } from './csv';

function csvFile(content: string) {
  return new File([content], 'processos.csv', { type: 'text/csv' });
}

describe('parser CSV da Fase 6', () => {
  it('aceita BOM, quoted fields e vírgula interna', async () => {
    const parsed = await parseCsvFile(
      csvFile(
        '\uFEFFcnj,cliente,tribunal,sistema,parte,papel,publicidade,monitoramento,observacoes\n"0004453-12.2026.8.16.0000","Cliente A","TJPR","PJe","Parte A","plaintiff","público","pausado","Observação, com vírgula"'
      )
    );
    expect(parsed.errors).toEqual([]);
    expect(parsed.rows[0]).toMatchObject({
      cnj: '00044531220268160000',
      clientName: 'Cliente A',
      notes: 'Observação, com vírgula',
      monitoringStatus: 'paused',
    });
  });

  it('retorna erros por linha sem descartar silenciosamente o problema', async () => {
    const parsed = await parseCsvFile(
      csvFile(
        'cnj,cliente,tribunal\n0004453-13.2026.8.16.0000,Cliente A,TJPR\n0004453-12.2026.8.16.0000,Cliente A,TJPR\n0004453-12.2026.8.16.0000,Cliente A,TJPR'
      )
    );
    expect(parsed.errors.length).toBeGreaterThanOrEqual(2);
    expect(
      parsed.errors.some((error) => error.message.includes('dígitos'))
    ).toBe(true);
    expect(
      parsed.errors.some((error) => error.message.includes('duplicado'))
    ).toBe(true);
  });

  it('bloqueia colunas ausentes e estados de monitoramento que não sejam pausados', async () => {
    const missing = await parseCsvFile(
      csvFile('cnj,cliente\n0004453-12.2026.8.16.0000,Cliente A')
    );
    expect(
      missing.errors.some((error) => error.message.includes('tribunal'))
    ).toBe(true);
    const active = await parseCsvFile(
      csvFile(
        'cnj,cliente,tribunal,monitoramento\n0004453-12.2026.8.16.0000,Cliente A,TJPR,ativo'
      )
    );
    expect(
      active.errors.some((error) => error.message.includes('pausado'))
    ).toBe(true);
  });

  it('aceita CSV vazio como estado explícito para a camada de ação rejeitar', async () => {
    const parsed = await parseCsvFile(csvFile(''));
    expect(parsed.empty).toBe(true);
    expect(parsed.rows).toEqual([]);
  });
});
