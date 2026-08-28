import { describe, expect, it } from 'vitest';
import {
  displayReportResult,
  displayReportStatus,
  reportContentHash,
  reportEditorialSchema,
} from './contract';

describe('report contract', () => {
  const input = {
    schemaVersion: 'report-v1',
    periodStartUtc: '2026-08-21T20:00:00.000Z',
    periodEndUtc: '2026-08-28T20:00:00.000Z',
    structuredContent: {
      processes: [{ process_id: 'p-1', changed: [] }],
      editorial: { summary_note: 'Nota' },
    },
    sourceManifest: { cutoff_utc: '2026-08-28T20:00:00.000Z' },
  } as const;

  it('produces the same hash regardless of object key order', () => {
    const first = reportContentHash(input);
    const second = reportContentHash({
      ...input,
      structuredContent: {
        editorial: { summary_note: 'Nota' },
        processes: [{ changed: [], process_id: 'p-1' }],
      },
      sourceManifest: { cutoff_utc: '2026-08-28T20:00:00.000Z' },
    });
    expect(first).toMatch(/^[0-9a-f]{64}$/);
    expect(second).toBe(first);
  });

  it('rejects unallowlisted editorial fields', () => {
    const parsed = reportEditorialSchema.safeParse({
      arbitrary: 'não permitido',
    });
    expect(parsed.success).toBe(false);
  });

  it('keeps report states and evidence labels distinct', () => {
    expect(displayReportStatus('cancelled')).toBe('Cancelado');
    expect(displayReportResult('changed')).toBe('Alteração detectada');
    expect(displayReportResult('unchanged')).toBe('Sem alteração comprovada');
    expect(displayReportResult('not_comparable')).toBe('Não comparável');
    expect(displayReportResult('failure')).toBe('Falha');
  });
});
