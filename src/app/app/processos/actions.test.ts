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

import { setProcessMonitoringStatusAction } from './actions';

function form(values: Record<string, string>) {
  const data = new FormData();
  Object.entries(values).forEach(([key, value]) => data.set(key, value));
  return data;
}

describe('Fase 9 monitoring action', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.requirePermission.mockResolvedValue({ profile: { role: 'lawyer' } });
    mocks.rpc.mockResolvedValue({ error: null });
    mocks.createClient.mockResolvedValue({ rpc: mocks.rpc });
  });

  it('valida o processo e usa somente a RPC de domínio', async () => {
    await expect(
      setProcessMonitoringStatusAction(
        form({
          processId: '91000000-0000-4000-8000-000000000008',
          status: 'active',
        })
      )
    ).resolves.toEqual({ success: true });

    expect(mocks.requirePermission).toHaveBeenCalledWith('manage_monitoring', {
      redirectOnDenied: false,
    });
    expect(mocks.rpc).toHaveBeenCalledWith(
      'phase9_set_process_monitoring_status',
      {
        p_process_id: '91000000-0000-4000-8000-000000000008',
        p_status: 'active',
      }
    );
    expect(mocks.revalidatePath).toHaveBeenCalledWith('/app/processos');
  });

  it('rejeita entrada inválida antes de abrir cliente ou chamar RPC', async () => {
    await expect(
      setProcessMonitoringStatusAction(
        form({ processId: 'not-a-uuid', status: 'active' })
      )
    ).resolves.toEqual({
      error: 'Informe um processo e um status de monitoramento válidos.',
    });
    expect(mocks.createClient).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('sanitiza a negação de autorização retornada pelo banco', async () => {
    mocks.rpc.mockResolvedValueOnce({
      error: { message: 'permission denied' },
    });
    await expect(
      setProcessMonitoringStatusAction(
        form({
          processId: '91000000-0000-4000-8000-000000000008',
          status: 'paused',
        })
      )
    ).resolves.toEqual({
      error: 'Você não tem autorização para esta operação.',
    });
  });

  it('solicita atualização manual via RPC com validação segura de actor e processo', async () => {
    const { requestProcessRefreshAction } = await import('./actions');
    mocks.requirePermission.mockResolvedValueOnce({
      profile: { id: 'user-123', role: 'lawyer' },
    });
    mocks.rpc.mockResolvedValueOnce({
      data: [{ job_id: 'job-123', is_reused: false }],
      error: null,
    });

    await expect(
      requestProcessRefreshAction(
        form({
          processId: '91000000-0000-4000-8000-000000000008',
        })
      )
    ).resolves.toEqual({
      success: true,
    });

    expect(mocks.rpc).toHaveBeenCalledWith(
      'realignment1_request_process_refresh',
      {
        p_process_id: '91000000-0000-4000-8000-000000000008',
      }
    );
    expect(mocks.revalidatePath).toHaveBeenCalledWith('/app');
    expect(mocks.revalidatePath).toHaveBeenCalledWith('/app/clientes');
    expect(mocks.revalidatePath).toHaveBeenCalledWith('/app/processos');
  });
});
