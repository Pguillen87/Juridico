// Exemplo conceitual dos testes de deduplicação e comparação para a PoC
import { describe, it, expect } from 'vitest';
import { QueryState, ProcessMovement, NormalizedProcess } from './types';

// Funções simuladas para a PoC
function generateStableHash(movement: any): string {
  // Simula um hash que ignora data exata de extração e foca no evento
  return `hash_${movement.codigo || 0}_${movement.nome.toLowerCase().replace(/\s/g, '')}_${movement.dataHora.split('T')[0]}`;
}

function compareSnapshots(oldSnap: NormalizedProcess | null, newSnap: NormalizedProcess): QueryState {
  if (!oldSnap) return 'success_with_changes'; // Baseline
  
  const oldHashes = new Set(oldSnap.movements.map(m => m.stableHash));
  const newHashes = newSnap.movements.map(m => m.stableHash);
  
  const hasNew = newHashes.some(hash => !oldHashes.has(hash));
  return hasNew ? 'success_with_changes' : 'success_without_changes';
}

describe('Motor de Comparação e Deduplicação', () => {
  const movA = { codigo: 26, nome: 'Distribuição', dataHora: '2024-03-15T08:32:00.000Z' };
  const movB = { codigo: 60, nome: 'Juntada de Petição', dataHora: '2024-03-22T14:10:00.000Z' };

  it('deve gerar o mesmo hash para movimentações equivalentes', () => {
    const hash1 = generateStableHash(movA);
    const hash2 = generateStableHash({ ...movA, dataHora: '2024-03-15T09:00:00.000Z' }); // Mesma data, hora diferente
    expect(hash1).toBe(hash2);
  });

  it('deve detectar alteração quando há novos movimentos (success_with_changes)', () => {
    const oldSnap: NormalizedProcess = {
      cnjNumber: '000123456720248260100', tribunal: 'tjsp', source: 'datajud',
      movements: [{ description: movA.nome, date: movA.dataHora, stableHash: generateStableHash(movA) }]
    };
    
    const newSnap: NormalizedProcess = {
      ...oldSnap,
      movements: [
        { description: movA.nome, date: movA.dataHora, stableHash: generateStableHash(movA) },
        { description: movB.nome, date: movB.dataHora, stableHash: generateStableHash(movB) }
      ]
    };

    expect(compareSnapshots(oldSnap, newSnap)).toBe('success_with_changes');
  });

  it('deve classificar como sem alteração quando não há movimentos novos (success_without_changes)', () => {
    const snap: NormalizedProcess = {
      cnjNumber: '000123456720248260100', tribunal: 'tjsp', source: 'datajud',
      movements: [{ description: movA.nome, date: movA.dataHora, stableHash: generateStableHash(movA) }]
    };

    // Nova consulta retorna exatamente os mesmos dados
    expect(compareSnapshots(snap, snap)).toBe('success_without_changes');
  });
});
