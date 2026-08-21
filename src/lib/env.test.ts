import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { env } from './env';
import { z } from 'zod';

describe('Environment Configuration', () => {
  it('deve ter um NODE_ENV definido', () => {
    expect(['development', 'test', 'production']).toContain(env.NODE_ENV);
  });

  describe('Supabase Environment Variables', () => {
    const originalEnv = process.env;

    beforeEach(() => {
      vi.resetModules();
      process.env = { ...originalEnv };
    });

    afterEach(() => {
      process.env = originalEnv;
    });

    it('deve validar configuração válida do Supabase', async () => {
      process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://valid-url.supabase.co';
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = 'valid-key';

      // Importar dinamicamente para forçar a re-avaliação
      const { env: reloadedEnv } = await import('./env');

      expect(reloadedEnv.NEXT_PUBLIC_SUPABASE_URL).toBe(
        'https://valid-url.supabase.co'
      );
      expect(reloadedEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY).toBe(
        'valid-key'
      );
    });

    it('deve permitir a ausência de variáveis do Supabase (opcionais)', async () => {
      delete process.env.NEXT_PUBLIC_SUPABASE_URL;
      delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

      const { env: reloadedEnv } = await import('./env');

      expect(reloadedEnv.NEXT_PUBLIC_SUPABASE_URL).toBeUndefined();
      expect(reloadedEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY).toBeUndefined();
    });

    it('não deve conter segredos no contrato client-side', () => {
      const keys = Object.keys(env);
      const secretKeys = keys.filter(
        (key) =>
          key.toLowerCase().includes('secret') ||
          key.toLowerCase().includes('service_role') ||
          key.toLowerCase().includes('password')
      );
      expect(secretKeys).toHaveLength(0);
    });
  });
});
