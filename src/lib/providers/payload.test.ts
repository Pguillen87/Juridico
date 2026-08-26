import { describe, expect, it } from 'vitest';
import {
  MAX_SANITIZED_PAYLOAD_BYTES,
  PayloadSanitizationError,
  sanitizeRawProviderPayload,
} from '@/lib/providers/payload';

describe('raw provider payload sanitization', () => {
  it('redige headers e chaves sensíveis antes do hash', () => {
    const sanitized = sanitizeRawProviderPayload({
      data: { processRef: 'synthetic-process-001' },
      Authorization: 'Bearer synthetic-secret-value',
      cookie: 'session=synthetic-secret-value',
      token: 'synthetic-token',
    });

    expect(sanitized.payload).toEqual({
      data: { processRef: 'synthetic-process-001' },
    });
    expect(sanitized.canonicalJson).not.toContain('synthetic-secret');
    expect(sanitized.payloadHash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('produz hash e bytes estáveis para chaves reordenadas', () => {
    const left = sanitizeRawProviderPayload({
      z: 2,
      a: { y: true, x: 'value' },
    });
    const right = sanitizeRawProviderPayload({
      a: { x: 'value', y: true },
      z: 2,
    });

    expect(left.canonicalJson).toBe(right.canonicalJson);
    expect(left.payloadHash).toBe(right.payloadHash);
    expect(left.payloadBytes).toBe(right.payloadBytes);
  });

  it('rejeita segredo embutido em valor e não apenas em nome de chave', () => {
    expect(() =>
      sanitizeRawProviderPayload({
        details: 'Authorization: Bearer synthetic-secret-value',
      })
    ).toThrow(PayloadSanitizationError);
  });

  it('rejeita estados de comparação no payload bruto', () => {
    expect(() =>
      sanitizeRawProviderPayload({
        observation: { processRef: 'synthetic-process-001' },
        changed: true,
      })
    ).toThrow('comparison states');
  });

  it('rejeita raiz inválida, conteúdo não JSON e limite de tamanho', () => {
    expect(() => sanitizeRawProviderPayload('invalid-root')).toThrow(
      PayloadSanitizationError
    );
    expect(() => sanitizeRawProviderPayload({ value: BigInt(1) })).toThrow(
      PayloadSanitizationError
    );
    expect(() =>
      sanitizeRawProviderPayload({
        oversized: 'x'.repeat(MAX_SANITIZED_PAYLOAD_BYTES),
      })
    ).toThrow(PayloadSanitizationError);
  });

  it('aceita arrays sintéticos pequenos e rejeita profundidade excessiva', () => {
    const array = sanitizeRawProviderPayload([
      { processRef: 'synthetic-process-001' },
      { processRef: 'synthetic-process-002' },
    ]);
    expect(Array.isArray(array.payload)).toBe(true);

    let nested: unknown = { value: 'x' };
    for (let index = 0; index < 25; index += 1) {
      nested = { nested };
    }
    expect(() => sanitizeRawProviderPayload(nested)).toThrow(
      PayloadSanitizationError
    );
  });
});
