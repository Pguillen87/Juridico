import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  requirePermission: vi.fn(),
  createAdminClient: vi.fn(),
  createClient: vi.fn(),
  appendInviteAuditInternal: vi.fn(),
  appendRejectionAuditInternal: vi.fn(),
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
  appendInviteAuditInternal: mocks.appendInviteAuditInternal,
  appendRejectionAuditInternal: mocks.appendRejectionAuditInternal,
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
    mocks.appendInviteAuditInternal.mockResolvedValue(1);
    mocks.appendRejectionAuditInternal.mockResolvedValue(1);
  });

  it('nega chamada direta de non-owner sem criar cliente administrativo', async () => {
    mocks.requirePermission.mockRejectedValue(
      new Error('redirect:/app?error=forbidden')
    );

    await expect(inviteUserAction(payload())).resolves.toEqual({
      error: 'Ocorreu um erro inesperado ao processar o convite.',
    });
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
    expect(mocks.appendInviteAuditInternal).not.toHaveBeenCalled();
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
      profile: { id: 'user-owner-id', office_id: 'office-owner' },
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
    expect(mocks.appendInviteAuditInternal).toHaveBeenCalledWith(
      'user-owner-id',
      'auth-user-1',
      'accepted'
    );
  });

  it('reconhece P0001 do last-owner em set_active e audita com código de máquina', async () => {
    const rpc = vi.fn().mockResolvedValue({
      error: {
        code: 'P0001',
        message:
          'Cannot remove or deactivate the last active owner of an office',
      },
    });
    mocks.requirePermission.mockResolvedValue({
      profile: { id: 'user-owner-id', office_id: 'office-owner' },
    });
    mocks.createClient.mockResolvedValue({ rpc });

    await expect(
      setActiveAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          isActive: 'false',
        })
      )
    ).resolves.toEqual({
      error:
        'Não é possível inativar o último administrador ativo do escritório.',
    });
    expect(mocks.appendRejectionAuditInternal).toHaveBeenCalledWith(
      'user-owner-id',
      'last_owner_blocked',
      'user_profile',
      '00000000-0000-4000-8000-000000000004',
      'deactivate_last_active_owner'
    );
  });

  it('reconhece P0001 do last-owner em set_owner e audita com código de máquina', async () => {
    const rpc = vi.fn().mockResolvedValue({
      error: {
        code: 'P0001',
        message:
          'Cannot remove or deactivate the last active owner of an office',
      },
    });
    mocks.requirePermission.mockResolvedValue({
      profile: { id: 'user-owner-id', office_id: 'office-owner' },
    });
    mocks.createClient.mockResolvedValue({ rpc });

    await expect(
      setOwnerAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          isOwner: 'false',
        })
      )
    ).resolves.toEqual({
      error:
        'Não é possível revogar o último administrador ativo do escritório.',
    });
    expect(mocks.appendRejectionAuditInternal).toHaveBeenCalledWith(
      'user-owner-id',
      'last_owner_blocked',
      'user_profile',
      '00000000-0000-4000-8000-000000000004',
      'revoke_last_active_owner'
    );
  });

  it('não confunde 42501 genérico com bloqueio de last-owner', async () => {
    const rpc = vi.fn().mockResolvedValue({
      error: { code: '42501', message: 'row-level security policy violation' },
    });
    mocks.requirePermission.mockResolvedValue({
      profile: { id: 'user-owner-id', office_id: 'office-owner' },
    });
    mocks.createClient.mockResolvedValue({ rpc });

    await expect(
      setActiveAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          isActive: 'false',
        })
      )
    ).resolves.toEqual({
      error: 'Você não tem autorização para esta operação.',
    });
    expect(mocks.appendRejectionAuditInternal).not.toHaveBeenCalled();
  });

  it('P0001 em operação não degradante não é tratado como last-owner', async () => {
    const rpc = vi.fn().mockResolvedValue({
      error: {
        code: 'P0001',
        message:
          'Cannot remove or deactivate the last active owner of an office',
      },
    });
    mocks.requirePermission.mockResolvedValue({
      profile: { id: 'user-owner-id', office_id: 'office-owner' },
    });
    mocks.createClient.mockResolvedValue({ rpc });

    await expect(
      setActiveAction(
        userPayload({
          userId: '00000000-0000-4000-8000-000000000004',
          isActive: 'true',
        })
      )
    ).resolves.toEqual({
      error:
        'Operação bloqueada: o escritório precisa manter um administrador ativo.',
    });
    expect(mocks.appendRejectionAuditInternal).not.toHaveBeenCalled();
  });

  it('compensa invite quando o audit accepted falha: remove profile e auth user recém-criados', async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const eq = vi.fn().mockResolvedValue({ error: null });
    const del = vi.fn().mockReturnValue({ eq });
    const deleteUser = vi.fn().mockResolvedValue({ error: null, data: {} });
    const admin = {
      auth: {
        admin: {
          inviteUserByEmail: vi.fn().mockResolvedValue({
            data: { user: { id: 'auth-user-1' } },
            error: null,
          }),
          deleteUser,
        },
      },
      from: vi.fn().mockReturnValue({ insert, delete: del }),
    };
    mocks.requirePermission.mockResolvedValue({
      profile: { id: 'user-owner-id', office_id: 'office-owner' },
    });
    mocks.createAdminClient.mockReturnValue(admin);
    mocks.appendInviteAuditInternal.mockRejectedValueOnce(
      new Error('audit down')
    );

    const result = await inviteUserAction(payload());
    expect(result.success).toBeUndefined();
    expect(result.error).toBeDefined();
    // Compensação atua somente sobre o usuário criado nesta operação
    expect(del).toHaveBeenCalledWith();
    expect(eq).toHaveBeenCalledWith('id', 'auth-user-1');
    expect(deleteUser).toHaveBeenCalledWith('auth-user-1');
    // Registra rejeição com código audit_error
    expect(mocks.appendInviteAuditInternal).toHaveBeenCalledWith(
      'user-owner-id',
      null,
      'rejected',
      'audit_error'
    );
  });

  it('reporta estado parcial quando a compensação do invite também falha', async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const eq = vi.fn().mockResolvedValue({ error: null });
    const del = vi.fn().mockReturnValue({ eq });
    const deleteUser = vi.fn().mockResolvedValue({
      error: { message: 'boom' },
      data: null,
    });
    const admin = {
      auth: {
        admin: {
          inviteUserByEmail: vi.fn().mockResolvedValue({
            data: { user: { id: 'auth-user-1' } },
            error: null,
          }),
          deleteUser,
        },
      },
      from: vi.fn().mockReturnValue({ insert, delete: del }),
    };
    mocks.requirePermission.mockResolvedValue({
      profile: { id: 'user-owner-id', office_id: 'office-owner' },
    });
    mocks.createAdminClient.mockReturnValue(admin);
    mocks.appendInviteAuditInternal.mockRejectedValueOnce(
      new Error('audit down')
    );

    const result = await inviteUserAction(payload());
    expect(result.success).toBeUndefined();
    expect(result.error).toContain('reversão ficou incompleta');
    expect(deleteUser).toHaveBeenCalledWith('auth-user-1');
  });
});
