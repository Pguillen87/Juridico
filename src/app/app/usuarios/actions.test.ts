import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  requirePermission: vi.fn(),
  createAdminClient: vi.fn(),
  createClient: vi.fn(),
  appendInviteAudit: vi.fn(),
  consumeAdminRateLimit: vi.fn(),
  isRateLimitAllowed: vi.fn(),
  revalidatePath: vi.fn(),
}));

vi.mock('@/lib/auth/guards', () => ({
  requirePermission: mocks.requirePermission,
}));
vi.mock('@/lib/supabase/admin', () => ({
  createAdminClient: mocks.createAdminClient,
}));
vi.mock('@/lib/supabase/server', () => ({
  createClient: mocks.createClient,
}));
vi.mock('@/lib/audit', () => ({
  appendInviteAudit: mocks.appendInviteAudit,
}));
vi.mock('@/lib/rate-limit', () => ({
  consumeAdminRateLimit: mocks.consumeAdminRateLimit,
  isRateLimitAllowed: mocks.isRateLimitAllowed,
}));
vi.mock('next/cache', () => ({ revalidatePath: mocks.revalidatePath }));

import {
  changeRoleAction,
  inviteUserAction,
  setActiveAction,
  setOwnerAction,
} from './actions';

function payload() {
  const formData = new FormData();
  formData.set('name', 'Operador Teste');
  formData.set('email', 'operator@example.test');
  formData.set('role', 'operator');
  formData.set('office_id', 'office-arbitrario');
  return formData;
}

function userPayload(fields: Record<string, string>) {
  const formData = new FormData();
  Object.entries(fields).forEach(([key, value]) => formData.set(key, value));
  return formData;
}

describe('Server Actions administrativas', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.consumeAdminRateLimit.mockResolvedValue({
      allowed: true,
      retryAfterSeconds: 0,
      currentCount: 1,
      limitCount: 5,
      windowSeconds: 900,
    });
    mocks.isRateLimitAllowed.mockReturnValue(true);
    mocks.appendInviteAudit.mockResolvedValue(1);
  });

  it('nega chamada direta de non-owner sem criar cliente administrativo', async () => {
    mocks.requirePermission.mockRejectedValue(
      new Error('redirect:/app?error=forbidden')
    );

    await expect(inviteUserAction(payload())).resolves.toEqual({
      error: 'Ocorreu um erro inesperado ao processar o convite.',
    });
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
    expect(mocks.appendInviteAudit).not.toHaveBeenCalled();
  });

  it('bloqueia change_role antes do RPC quando o rate limit excede a janela', async () => {
    mocks.requirePermission.mockResolvedValue({});
    mocks.consumeAdminRateLimit.mockResolvedValue({
      allowed: false,
      retryAfterSeconds: 120,
      currentCount: 21,
      limitCount: 20,
      windowSeconds: 900,
    });
    mocks.isRateLimitAllowed.mockReturnValue(false);

    await expect(
      changeRoleAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          role: 'reviewer',
        })
      )
    ).resolves.toEqual({
      error: 'Operação temporariamente limitada. Tente novamente mais tarde.',
      retryAfterSeconds: 120,
    });
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  it('envia somente os argumentos canônicos do change_role ao RPC', async () => {
    const rpc = vi.fn().mockResolvedValue({ error: null });
    mocks.requirePermission.mockResolvedValue({});
    mocks.createClient.mockResolvedValue({ rpc });

    await expect(
      changeRoleAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          role: 'reviewer',
        })
      )
    ).resolves.toEqual({ success: true });
    expect(rpc).toHaveBeenCalledWith('change_user_role', {
      p_target_user_id: '00000000-0000-4000-8000-000000000004',
      p_new_role: 'reviewer',
    });
  });

  it('normaliza booleanos e usa RPCs distintos para status e owner', async () => {
    const rpc = vi.fn().mockResolvedValue({ error: null });
    mocks.requirePermission.mockResolvedValue({});
    mocks.createClient.mockResolvedValue({ rpc });

    await expect(
      setActiveAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          isActive: 'false',
        })
      )
    ).resolves.toEqual({ success: true });
    await expect(
      setOwnerAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          isOwner: 'true',
        })
      )
    ).resolves.toEqual({ success: true });
    expect(rpc).toHaveBeenNthCalledWith(1, 'set_user_active', {
      p_target_user_id: '00000000-0000-4000-8000-000000000004',
      p_is_active: false,
    });
    expect(rpc).toHaveBeenNthCalledWith(2, 'set_user_owner', {
      p_target_user_id: '00000000-0000-4000-8000-000000000004',
      p_is_owner: true,
    });
  });

  it('ignora office_id do formulário e usa o office do owner', async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const admin = {
      auth: {
        admin: {
          inviteUserByEmail: vi.fn().mockResolvedValue({
            data: { user: { id: 'auth-user-1' } },
            error: null,
          }),
          deleteUser: vi.fn(),
        },
      },
      from: vi.fn().mockReturnValue({ insert }),
    };
    mocks.requirePermission.mockResolvedValue({
      profile: { office_id: 'office-owner' },
    });
    mocks.createAdminClient.mockReturnValue(admin);

    await expect(inviteUserAction(payload())).resolves.toEqual({
      success: true,
    });
    expect(insert).toHaveBeenCalledWith({
      id: 'auth-user-1',
      office_id: 'office-owner',
      name: 'Operador Teste',
      role: 'operator',
      is_active: true,
      is_owner: false,
    });
    expect(mocks.appendInviteAudit).toHaveBeenCalledWith(
      'auth-user-1',
      'accepted'
    );
  });
});
