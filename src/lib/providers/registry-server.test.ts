import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));

import { createDefaultProviderRegistry } from './registry-server';

describe('operational provider registry', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('does not select the synthetic sandbox when fake configuration is present', async () => {
    vi.stubEnv('DATAJUD_TRANSPORT_MODE', 'fake');
    vi.stubEnv('DATAJUD_MOCK_SERVER', 'true');
    vi.stubEnv('DATAJUD_API_KEY', '');
    vi.stubEnv('DATAJUD_API_URL', '');

    const registry = createDefaultProviderRegistry();

    expect(registry.getProvider('datajud_sandbox')).toBeUndefined();
    expect(registry.getProvider('datajud_public')).toBeDefined();
  });
});
