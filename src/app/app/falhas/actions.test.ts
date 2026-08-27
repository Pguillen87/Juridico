import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  requirePermission: vi.fn(),
  createClient: vi.fn(),
  revalidatePath: vi.fn(),
  rpc: vi.fn(),
}));

vi.mock('@/lib/auth/guards', () => ({
  requirePermission: mocks.requirePermission,
}));
vi.mock('@/lib/supabase/server', () => ({ createClient: mocks.createClient }));
vi.mock('next/cache', () => ({ revalidatePath: mocks.revalidatePath }));

import {
  addFailureNoteAction,
  assignFailureAction,
  requestFailureReprocessAction,
  resolveFailureAction,
} from './actions';

function form(values: Record<string, string>) {
  const data = new FormData();
  Object.entries(values).forEach(([key, value]) => data.set(key, value));
  return data;
}

describe('Fase 11 — ações da central', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.requirePermission.mockResolvedValue({ profile: { role: 'lawyer' } });
    mocks.rpc.mockResolvedValue({ data: 'ok', error: null });
    mocks.createClient.mockResolvedValue({ rpc: mocks.rpc });
  });

  it('reprocessa somente com a permissão manual_reprocess', async () => {
    await expect(
      requestFailureReprocessAction(
        form({
          incidentId: '91000000-0000-4000-8000-000000000008',
          idempotencyKey: 'ui-reprocess-v1',
        })
      )
    ).resolves.toEqual({ success: true, jobId: 'ok' });
    expect(mocks.requirePermission).toHaveBeenCalledWith('manual_reprocess', {
      redirectOnDenied: false,
    });
    expect(mocks.rpc).toHaveBeenCalledWith(
      'phase11_request_failure_reprocess',
      {
        p_incident_id: '91000000-0000-4000-8000-000000000008',
        p_idempotency_key: 'ui-reprocess-v1',
      }
    );
  });

  it('valida entrada antes de abrir o cliente', async () => {
    await expect(
      addFailureNoteAction(
        form({ incidentId: 'not-uuid', note: '', idempotencyKey: 'bad' })
      )
    ).resolves.toEqual({ error: 'Informe uma observação válida.' });
    expect(mocks.createClient).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('usa ações de domínio separadas para resolução, atribuição e observação', async () => {
    await resolveFailureAction(
      form({
        incidentId: '91000000-0000-4000-8000-000000000008',
        resolutionCode: 'closed_by_operator',
        resolutionNote: 'Falha analisada no ambiente sintético.',
        idempotencyKey: 'resolve-v1',
      })
    );
    await assignFailureAction(
      form({
        incidentId: '91000000-0000-4000-8000-000000000008',
        assigneeUserId: '91000000-0000-4000-8000-000000000009',
        idempotencyKey: 'assign-v1',
      })
    );
    expect(mocks.rpc).toHaveBeenNthCalledWith(
      1,
      'phase11_resolve_failure_incident',
      expect.objectContaining({ p_resolution_code: 'closed_by_operator' })
    );
    expect(mocks.rpc).toHaveBeenNthCalledWith(
      2,
      'phase11_assign_failure_incident',
      expect.objectContaining({
        p_assignee_user_id: '91000000-0000-4000-8000-000000000009',
      })
    );
  });

  it('não expõe mensagem técnica do banco', async () => {
    mocks.rpc.mockResolvedValueOnce({
      error: { message: 'permission denied' },
    });
    await expect(
      requestFailureReprocessAction(
        form({
          incidentId: '91000000-0000-4000-8000-000000000008',
          idempotencyKey: 'ui-reprocess-v2',
        })
      )
    ).resolves.toEqual({
      error: 'Você não tem autorização para esta operação.',
    });
  });
});
