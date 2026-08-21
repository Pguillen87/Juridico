import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));

import { createAdminClient } from './admin';

describe('admin client do Supabase', () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'http://127.0.0.1:54321');
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', '');
  });

  it('falha fechado quando a chave elevada não está configurada', () => {
    expect(() => createAdminClient()).toThrow(
      'As credenciais administrativas do Supabase não estão configuradas.'
    );
  });

  it('permanece dependente de chave server-only quando configurada', () => {
    vi.stubEnv('SUPABASE_SERVICE_ROLE_KEY', 'test-only-service-role-key');
    expect(() => createAdminClient()).not.toThrow();
  });
});
