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
  confirmRelatedPartyAction,
  createClientAction,
  createPartyAction,
  createRelatedPartyAction,
  updatePartyAction,
} from './actions';

function form(values: Record<string, string>) {
  const data = new FormData();
  Object.entries(values).forEach(([key, value]) => data.set(key, value));
  return data;
}

describe('Fase 5 client actions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.requirePermission.mockResolvedValue({ profile: { role: 'lawyer' } });
    mocks.rpc.mockResolvedValue({ error: null });
    mocks.createClient.mockResolvedValue({ rpc: mocks.rpc });
  });

  it('rejeita nome vazio ou menor que dois caracteres antes do RPC', async () => {
    await expect(
      createPartyAction(form({ partyType: 'person', displayName: ' x ' }))
    ).resolves.toEqual({ error: 'Informe tipo e nome válidos.' });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('normaliza display_name por trim antes de chamar create party', async () => {
    await expect(
      createPartyAction(
        form({ partyType: 'person', displayName: '  Maria Silva  ' })
      )
    ).resolves.toEqual({ success: true });
    expect(mocks.rpc).toHaveBeenCalledWith('create_party', {
      p_party_type: 'person',
      p_display_name: 'Maria Silva',
    });
  });

  it('rejeita tipo desconhecido', async () => {
    await expect(
      createClientAction(
        form({ partyType: 'person;drop', displayName: 'Cliente' })
      )
    ).resolves.toEqual({ error: 'Informe tipo e nome válidos.' });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('respeita o limite máximo do nome', async () => {
    await expect(
      createClientAction(
        form({ partyType: 'company', displayName: 'a'.repeat(201) })
      )
    ).resolves.toEqual({ error: 'Informe tipo e nome válidos.' });
  });

  it('não aceita campos de relação malformados', async () => {
    await expect(
      createRelatedPartyAction(
        form({
          clientId: 'not-uuid',
          partyId: 'not-uuid',
          relationType: 'family',
        })
      )
    ).resolves.toEqual({ error: 'Os dados da relação são inválidos.' });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('encaminha relação por IDs e não por nomes', async () => {
    await expect(
      createRelatedPartyAction(
        form({
          clientId: '00000000-0000-4000-8000-000000000001',
          partyId: '00000000-0000-4000-8000-000000000002',
          relationType: 'family_member',
          notes: '  observação  ',
        })
      )
    ).resolves.toEqual({ success: true });
    expect(mocks.rpc).toHaveBeenCalledWith(
      'create_client_related_party',
      expect.objectContaining({
        p_client_id: '00000000-0000-4000-8000-000000000001',
        p_party_id: '00000000-0000-4000-8000-000000000002',
        p_relation_type: 'family_member',
      })
    );
  });

  it('mapeia permission denied para mensagem segura', async () => {
    mocks.rpc.mockResolvedValueOnce({
      error: { message: 'permission denied by policy' },
    });
    await expect(
      updatePartyAction(
        form({
          id: '00000000-0000-4000-8000-000000000003',
          partyType: 'company',
          displayName: 'Parte',
        })
      )
    ).resolves.toEqual({
      error: 'Você não tem autorização para esta operação.',
    });
  });

  it('usa RPC de domínio para confirmação', async () => {
    await expect(
      confirmRelatedPartyAction(
        form({ relationId: '00000000-0000-4000-8000-000000000004' })
      )
    ).resolves.toEqual({ success: true });
    expect(mocks.rpc).toHaveBeenCalledWith('confirm_client_related_party', {
      p_relation_id: '00000000-0000-4000-8000-000000000004',
    });
  });
});
