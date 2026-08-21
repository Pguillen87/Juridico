import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  requireOwnerProfile: vi.fn(),
  createAdminClient: vi.fn(),
  revalidatePath: vi.fn(),
}));

vi.mock('@/lib/auth/guards', () => ({
  requireOwnerProfile: mocks.requireOwnerProfile,
}));
vi.mock('@/lib/supabase/admin', () => ({
  createAdminClient: mocks.createAdminClient,
}));
vi.mock('next/cache', () => ({ revalidatePath: mocks.revalidatePath }));

import { inviteUserAction } from './actions';

function payload() {
  const formData = new FormData();
  formData.set('name', 'Operador Teste');
  formData.set('email', 'operator@example.test');
  formData.set('role', 'operator');
  formData.set('office_id', 'office-arbitrario');
  return formData;
}

describe('Server Action de convite', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('nega chamada direta de non-owner sem criar cliente administrativo', async () => {
    mocks.requireOwnerProfile.mockRejectedValue(
      new Error('redirect:/app?error=forbidden')
    );

    await expect(inviteUserAction(payload())).resolves.toEqual({
      error: 'Ocorreu um erro inesperado ao processar o convite.',
    });
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
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
    mocks.requireOwnerProfile.mockResolvedValue({
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
  });
});
