import { describe, it, expect } from 'vitest';
import { env } from './env';

describe('Environment Configuration', () => {
  it('deve ter um NODE_ENV definido', () => {
    expect(['development', 'test', 'production']).toContain(env.NODE_ENV);
  });
});
