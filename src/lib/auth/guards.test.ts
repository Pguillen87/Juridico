import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  createClient: vi.fn(),
  redirect: vi.fn(),
}));

vi.mock('@/lib/supabase/server', () => ({ createClient: mocks.createClient }));
vi.mock('next/navigation', () => ({ redirect: mocks.redirect }));

import {
  requireAuthenticatedProfile,
  requireOwnerProfile,
  roleLabel,
  safeInternalRedirect,
} from './guards';

function setupContext(
  isOwner = true,
  profileActive = true,
  officeActive = true
) {
  const user = { id: 'user-1', email: 'owner@example.test' } as never;
  const profile = {
    id: 'profile-1',
    office_id: 'office-1',
    name: 'Owner Teste',
    role: 'lawyer',
    is_active: profileActive,
    is_owner: isOwner,
    office_name: 'Escritório Teste',
  };
  const office = {
    id: 'office-1',
    name: 'Escritório Teste',
    is_active: officeActive,
  };
  const client = {
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user }, error: null }),
    },
    rpc: vi.fn().mockResolvedValue({ data: [profile], error: null }),
    from: vi.fn().mockReturnValue({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          maybeSingle: vi.fn().mockResolvedValue({ data: office, error: null }),
        }),
      }),
    }),
  };
  mocks.createClient.mockResolvedValue(client);
  return { user, profile, office };
}

describe('guards de autenticação', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.redirect.mockImplementation((path: string) => {
      throw new Error(`redirect:${path}`);
    });
  });

  it('resolve contexto confiável apenas após auth, profile e office', async () => {
    const expected = setupContext();
    await expect(requireAuthenticatedProfile()).resolves.toEqual(expected);
  });

  it('nega acesso administrativo a non-owner', async () => {
    setupContext(false);
    await expect(requireOwnerProfile()).rejects.toThrow(
      'redirect:/app?error=forbidden'
    );
  });

  it('nega perfil ou escritório inativos', async () => {
    setupContext(true, false, true);
    await expect(requireAuthenticatedProfile()).rejects.toThrow(
      'redirect:/login?error=inactive'
    );

    setupContext(true, true, false);
    await expect(requireAuthenticatedProfile()).rejects.toThrow(
      'redirect:/login?error=inactive'
    );
  });

  it('mantém somente destinos internos permitidos', () => {
    expect(safeInternalRedirect('/app')).toBe('/app');
    expect(safeInternalRedirect('/app/usuarios')).toBe('/app/usuarios');
    expect(safeInternalRedirect('/redefinir-senha')).toBe('/redefinir-senha');
    expect(safeInternalRedirect('https://evil.example')).toBe('/app');
    expect(safeInternalRedirect(null)).toBe('/app');
    expect(roleLabel('operator')).toBe('Operador');
  });
});
