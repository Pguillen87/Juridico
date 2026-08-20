import { describe, it, expect } from 'vitest';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { generateMovementHash, generateSnapshotHash, compareSnapshots } = require('./comparison.js');

describe('Motor de Comparação e Deduplicação (Módulo Compartilhado)', () => {
  const cnj = '00044531220268160000';
  
  it('deve gerar o mesmo hash para movimentações exatamente iguais', () => {
    const mov1 = { codigo: 1, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.000Z' };
    const mov2 = { codigo: 1, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.000Z' };
    expect(generateMovementHash(cnj, mov1)).toBe(generateMovementHash(cnj, mov2));
  });

  it('deve gerar o mesmo hash quando a diferença for apenas nos milissegundos (volatilidade tratada)', () => {
    const mov1 = { codigo: 1, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.000Z' };
    const mov2 = { codigo: 1, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.999Z' };
    expect(generateMovementHash(cnj, mov1)).toBe(generateMovementHash(cnj, mov2));
  });

  it('deve gerar hash diferente se o código for diferente', () => {
    const mov1 = { codigo: 1, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.000Z' };
    const mov2 = { codigo: 2, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.000Z' };
    expect(generateMovementHash(cnj, mov1)).not.toBe(generateMovementHash(cnj, mov2));
  });

  it('deve gerar hash diferente se a descrição for diferente', () => {
    const mov1 = { codigo: 1, nome: 'Distribuição', dataHora: '2026-01-01T10:00:00.000Z' };
    const mov2 = { codigo: 1, nome: 'Distribuição Sorteio', dataHora: '2026-01-01T10:00:00.000Z' };
    expect(generateMovementHash(cnj, mov1)).not.toBe(generateMovementHash(cnj, mov2));
  });

  it('deve gerar o mesmo snapshot para ordem diferente das mesmas movimentações', () => {
    const m1 = { stableHash: 'hash1' };
    const m2 = { stableHash: 'hash2' };
    expect(generateSnapshotHash(cnj, [m1, m2])).toBe(generateSnapshotHash(cnj, [m2, m1]));
  });

  describe('Deduplicação real dentro do mesmo payload', () => {
    it('deve gerar o mesmo snapshot para [A] e [A, A]', () => {
      const mA = { stableHash: 'hashA' };
      expect(generateSnapshotHash(cnj, [mA])).toBe(generateSnapshotHash(cnj, [mA, mA]));
    });

    it('deve gerar o mesmo snapshot para [A, B] e [B, A, A, B]', () => {
      const mA = { stableHash: 'hashA' };
      const mB = { stableHash: 'hashB' };
      expect(generateSnapshotHash(cnj, [mA, mB])).toBe(generateSnapshotHash(cnj, [mB, mA, mA, mB]));
    });

    it('deve gerar snapshots diferentes para [A] e [A, B]', () => {
      const mA = { stableHash: 'hashA' };
      const mB = { stableHash: 'hashB' };
      expect(generateSnapshotHash(cnj, [mA])).not.toBe(generateSnapshotHash(cnj, [mA, mB]));
    });
  });

  it('deve gerar snapshot diferente para nova movimentação', () => {
    const m1 = { stableHash: 'hash1' };
    const m2 = { stableHash: 'hash2' };
    expect(generateSnapshotHash(cnj, [m1])).not.toBe(generateSnapshotHash(cnj, [m1, m2]));
  });

  it('deve classificar como success_without_changes quando os snapshots são idênticos', () => {
    const snap1 = generateSnapshotHash(cnj, [{ stableHash: 'hash1' }]);
    const snap2 = generateSnapshotHash(cnj, [{ stableHash: 'hash1' }]);
    expect(compareSnapshots(snap1, snap2)).toBe('success_without_changes');
  });

  it('deve classificar como success_with_changes quando há alteração real', () => {
    const snap1 = generateSnapshotHash(cnj, [{ stableHash: 'hash1' }]);
    const snap2 = generateSnapshotHash(cnj, [{ stableHash: 'hash1' }, { stableHash: 'hash2' }]);
    expect(compareSnapshots(snap1, snap2)).toBe('success_with_changes');
  });

  describe('Regressão de Baseline (primeira consulta válida)', () => {
    it('deve retornar success_with_changes após timeout (snapshot anterior null)', () => {
      const snap2 = generateSnapshotHash(cnj, [{ stableHash: 'hash1' }]);
      expect(compareSnapshots(null, snap2)).toBe('success_with_changes');
    });

    it('deve retornar success_with_changes após source_unavailable (snapshot anterior null)', () => {
      const snap2 = generateSnapshotHash(cnj, [{ stableHash: 'hash1' }]);
      expect(compareSnapshots(null, snap2)).toBe('success_with_changes');
    });
  });
});
