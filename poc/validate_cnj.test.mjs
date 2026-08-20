import { describe, it, expect } from 'vitest';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { validateCnj, calculateCheckDigits } = require('./validate_cnj.js');

describe('Validador CNJ', () => {
  it('deve aprovar um CNJ válido do TJPR e retornar endpoint api_publica_tjpr', () => {
    const res = validateCnj('0004453-12.2026.8.16.0000');
    expect(res.isValid).toBe(true);
    expect(res.endpointAlias).toBe('api_publica_tjpr');
    expect(res.clean).toBe('00044531220268160000');
  });

  it('deve rejeitar CNJ com tamanho inválido', () => {
    const res = validateCnj('0004453-12.2026.8.16.000'); // Faltando 1 dígito
    expect(res.isValid).toBe(false);
    expect(res.isValidLength).toBe(false);
    expect(res.reason).toMatch(/Tamanho inválido/);
  });

  it('deve rejeitar CNJ com dígito verificador inválido', () => {
    // 0004453-12.2026.8.16.0000 é válido, então 99 será inválido
    const res = validateCnj('0004453-99.2026.8.16.0000');
    expect(res.isValid).toBe(false);
    expect(res.checkDigitsValid).toBe(false);
    expect(res.reason).toMatch(/Dígitos verificadores inválidos/);
  });

  it('deve rejeitar CNJ de outro tribunal (ex: TJSP - 8.26)', () => {
    // Dígitos verificadores simulados para passar na validação matemática se necessário
    // Base: 0001234 2024 8 26 0100 => 000123420248260100
    const base = '000123420248260100';
    const dv = calculateCheckDigits('00012340020248260100'); // Mock para pegar DV correto
    const cnjTjsp = `0001234-${dv}.2024.8.26.0100`;
    
    const res = validateCnj(cnjTjsp);
    expect(res.isValid).toBe(false);
    expect(res.endpointAlias).toBeNull();
    expect(res.reason).toMatch(/não corresponde ao TJPR/);
  });

  it('deve rejeitar CNJ de outro segmento (ex: TRT - 5.15)', () => {
    const dv = calculateCheckDigits('00012340020245150100');
    const cnjTrt = `0001234-${dv}.2024.5.15.0100`;
    
    const res = validateCnj(cnjTrt);
    expect(res.isValid).toBe(false);
    expect(res.endpointAlias).toBeNull();
    expect(res.reason).toMatch(/não corresponde ao TJPR/);
  });
});
