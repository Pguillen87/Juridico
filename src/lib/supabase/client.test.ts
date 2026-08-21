import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

describe('Supabase Browser Client', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    vi.resetModules();
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('deve lançar erro claro quando URL ou key estiverem ausentes', async () => {
    // Garantir que as variáveis estão ausentes
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

    // Importar dinamicamente para avaliar o código com as variáveis ausentes
    try {
      const { createClient } = await import('./client');
      createClient();
      // Se não lançar erro, o teste falha
      expect.fail(
        'Deveria ter lançado um erro por falta de variáveis de ambiente'
      );
    } catch (error: unknown) {
      if (error instanceof Error) {
        expect(error.message).toContain(
          'Missing Supabase environment variables'
        );
      } else {
        expect.fail('O erro capturado não é uma instância de Error');
      }
    }
  });
});
