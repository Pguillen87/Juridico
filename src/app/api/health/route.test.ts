import { describe, it, expect } from 'vitest';
import { GET } from './route';

describe('Health Check API', () => {
  it('deve retornar status ok', async () => {
    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data).toEqual({ status: 'ok' });
  });
});
