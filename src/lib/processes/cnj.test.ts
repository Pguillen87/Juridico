import { describe, expect, it } from 'vitest';
import { formatCnj, normalizeCnj, validateCnj } from './cnj';

describe('validador CNJ da Fase 6', () => {
  it('normaliza máscara e aceita segmento/tribunal fora do recorte TJPR', () => {
    const base = '0000000' + '2026' + '1' + '01' + '0000';
    const digits = String(
      98 - Number((BigInt(base) * BigInt(100)) % BigInt(97))
    ).padStart(2, '0');
    const cnj = `0000000-${digits}.2026.1.01.0000`;
    expect(normalizeCnj(cnj)).toBe(`0000000${digits}20261010000`);
    expect(formatCnj(cnj)).toBe(cnj);
  });

  it('rejeita tamanho e dígitos verificadores inválidos', () => {
    expect(validateCnj('123')).toMatchObject({
      valid: false,
      normalized: null,
    });
    expect(() => normalizeCnj('0004453-13.2026.8.16.0000')).toThrow(
      /dígitos verificadores/
    );
  });
});
