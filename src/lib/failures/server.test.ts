import { describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));

import {
  recordComparisonPersistenceFailure,
  reconcileExecutionFailure,
  reconcileSuccessfulExecution,
} from './server';

describe('Fase 11 — reconciliador server-only', () => {
  it('registra falha de execução somente pela RPC interna', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValue({ data: ['incident-id'], error: null });

    await expect(
      reconcileExecutionFailure('91000000-0000-4000-e000-000000000001', { rpc })
    ).resolves.toBe('incident-id');
    expect(rpc).toHaveBeenCalledWith(
      'phase11_record_execution_failure_internal',
      {
        p_execution_id: '91000000-0000-4000-e000-000000000001',
      }
    );
  });

  it('reconcilia recuperação sem falhar o worker quando a RPC interna falha', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValue({ data: null, error: { message: 'failed' } });

    await expect(
      reconcileSuccessfulExecution('91000000-0000-4000-e000-000000000001', {
        rpc,
      })
    ).resolves.toBe(0);
  });

  it('registra comparação como falha sem enviar diff ou payload bruto', async () => {
    const rpc = vi
      .fn()
      .mockResolvedValue({ data: ['incident-id'], error: null });

    await recordComparisonPersistenceFailure(
      {
        officeId: '91000000-0000-4000-9000-000000000001',
        processId: '91000000-0000-4000-c000-000000000001',
        providerId: 'datajud_sandbox',
        capability: 'process_observation',
        snapshotId: '91000000-0000-4000-b000-000000000001',
      },
      { rpc }
    );

    expect(rpc).toHaveBeenCalledWith(
      'phase11_record_failure_event_internal',
      expect.objectContaining({
        p_failure_code: 'comparison_persistence_failed',
        p_source_type: 'process_comparison',
        p_source_id: '91000000-0000-4000-b000-000000000001',
      })
    );
    expect(JSON.stringify(rpc.mock.calls)).not.toContain('normalized_diff');
    expect(JSON.stringify(rpc.mock.calls)).not.toContain('raw_payload');
  });
});
