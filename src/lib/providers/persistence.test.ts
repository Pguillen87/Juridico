import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));

const rpc = vi.fn();
const getUser = vi.fn();

vi.mock('@/lib/supabase/server', () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser },
  })),
}));

vi.mock('@/lib/supabase/admin', () => ({
  createAdminClient: vi.fn(() => ({ rpc })),
}));

import { type ProviderRequestV1 } from './contract';
import { providerFingerprint } from './normalize';
import { getProviderRawPayload, observeDataJudAndPersist } from './persistence';

function request(): ProviderRequestV1 {
  return {
    contractVersion: 1,
    operation: 'observe_process',
    capability: 'process_observation',
    subjectRef: { type: 'process', value: 'synthetic-process-001' },
    requestFingerprint: providerFingerprint({
      operation: 'observe_process',
      subjectRef: 'synthetic-process-001',
    }),
    correlationId: 'synthetic-correlation-backend-001',
    requestedAt: '2026-01-01T00:00:00.000Z',
    executionContext: {
      kind: 'user',
      actorUserId: 'synthetic-actor-001',
      officeId: 'synthetic-office-001',
      role: 'lawyer',
      isOwner: false,
    },
  };
}

describe('provider persistence backend-only', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getUser.mockResolvedValue({
      data: { user: { id: 'synthetic-session-actor-001' } },
      error: null,
    });
    rpc.mockImplementation(async (name: string) => {
      if (name === 'record_provider_exchange_internal') {
        return { data: 'synthetic-exchange-001', error: null };
      }
      if (name === 'get_provider_raw_payload_internal') {
        return { data: [{ payload: { outcome: 'observation' } }], error: null };
      }
      return { data: null, error: null };
    });
  });

  it('faz preflight e persiste somente pela RPC interna com actor da sessão', async () => {
    const result = await observeDataJudAndPersist(
      'synthetic-process-id-001',
      request()
    );

    expect(result.exchangeId).toBe('synthetic-exchange-001');
    expect(result.result.kind).toBe('observation');
    expect(rpc).toHaveBeenNthCalledWith(
      1,
      'require_provider_process_eligible_internal',
      {
        p_actor_user_id: 'synthetic-session-actor-001',
        p_process_id: 'synthetic-process-id-001',
      }
    );
    expect(rpc).toHaveBeenNthCalledWith(
      2,
      'record_provider_exchange_internal',
      expect.objectContaining({
        p_actor_user_id: 'synthetic-session-actor-001',
        p_process_id: 'synthetic-process-id-001',
        p_provider_id: 'datajud_sandbox',
        p_source: 'datajud',
      })
    );
    expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
      'record_provider_exchange'
    );
  });

  it('lê raw payload somente pela RPC interna com actor da sessão', async () => {
    const payload = await getProviderRawPayload('synthetic-exchange-001');

    expect(payload).toEqual([{ payload: { outcome: 'observation' } }]);
    expect(rpc).toHaveBeenCalledWith('get_provider_raw_payload_internal', {
      p_actor_user_id: 'synthetic-session-actor-001',
      p_exchange_id: 'synthetic-exchange-001',
    });
    expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
      'get_provider_raw_payload'
    );
  });

  it('falha fechado sem sessão e não chama o cliente admin', async () => {
    getUser.mockResolvedValue({ data: { user: null }, error: null });

    const result = await observeDataJudAndPersist(
      'synthetic-process-id-001',
      request()
    );

    expect(result.result).toMatchObject({
      kind: 'failure',
      errorCode: 'provider_backend_unauthorized',
    });
    expect(rpc).not.toHaveBeenCalled();
  });
});
