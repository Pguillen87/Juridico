import { describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));

import { generateWeeklyReport } from './generator';

describe('generateWeeklyReport', () => {
  it('calls the backend RPC with the controlled period inputs', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: [
        {
          report_id: '00000000-0000-4000-8000-000000000001',
          version_id: '00000000-0000-4000-8000-000000000002',
          replayed: false,
        },
      ],
      error: null,
    });

    const result = await generateWeeklyReport(
      {
        officeId: '00000000-0000-4000-8000-000000000003',
        clientId: '00000000-0000-4000-8000-000000000004',
        periodStartUtc: '2026-08-21T20:00:00.000Z',
        periodEndUtc: '2026-08-28T20:00:00.000Z',
        asOfUtc: '2026-08-28T21:00:00.000Z',
      },
      { rpc }
    );

    expect(result).toEqual({
      reportId: '00000000-0000-4000-8000-000000000001',
      versionId: '00000000-0000-4000-8000-000000000002',
      replayed: false,
    });
    expect(rpc).toHaveBeenCalledWith('phase12_generate_weekly_report', {
      p_office_id: '00000000-0000-4000-8000-000000000003',
      p_client_id: '00000000-0000-4000-8000-000000000004',
      p_period_start_utc: '2026-08-21T20:00:00.000Z',
      p_period_end_utc: '2026-08-28T20:00:00.000Z',
      p_as_of_utc: '2026-08-28T21:00:00.000Z',
    });
  });

  it('fails closed when the RPC returns an error or malformed data', async () => {
    const rpcError = vi.fn().mockResolvedValue({
      data: null,
      error: { message: 'manual_review_required: internal detail' },
    });
    await expect(
      generateWeeklyReport(
        {
          officeId: '00000000-0000-4000-8000-000000000003',
          clientId: '00000000-0000-4000-8000-000000000004',
        },
        { rpc: rpcError }
      )
    ).rejects.toThrow('Não foi possível gerar o relatório semanal.');

    const malformedRpc = vi.fn().mockResolvedValue({
      data: { report_id: '', version_id: null },
      error: null,
    });
    await expect(
      generateWeeklyReport(
        {
          officeId: '00000000-0000-4000-8000-000000000003',
          clientId: '00000000-0000-4000-8000-000000000004',
        },
        { rpc: malformedRpc }
      )
    ).rejects.toThrow('Resposta de geração inválida: report_id.');
  });
});
