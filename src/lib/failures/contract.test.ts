import { describe, expect, it } from 'vitest';

import {
  attemptLabel,
  failureClassFromCode,
  failureClassLabel,
  sanitizeFailureMessage,
} from './contract';

describe('Fase 11 — contrato de falhas', () => {
  it('classifica códigos sem usar mensagem livre ou fuzzy matching', () => {
    expect(failureClassFromCode('datajud_timeout')).toBe('provider_transient');
    expect(failureClassFromCode('comparison_persistence_failed')).toBe(
      'comparison'
    );
    expect(failureClassFromCode('scheduler_failure')).toBe('scheduler');
  });

  it('mantém a tentativa ausente como não aplicável', () => {
    expect(attemptLabel(null)).toBe('Não se aplica');
    expect(attemptLabel(2)).toBe('Tentativa 2');
  });

  it('não transforma unchanged em falha', () => {
    expect(failureClassLabel('provider_permanent')).toContain(
      'não recuperável'
    );
    expect(sanitizeFailureMessage('unchanged')).toBe(
      'Não foi possível concluir a operação.'
    );
  });

  it('sanitiza mensagens de autorização e não repassa detalhes do banco', () => {
    expect(sanitizeFailureMessage('permission denied by policy')).toBe(
      'Você não tem autorização para esta operação.'
    );
    expect(sanitizeFailureMessage('SQLSTATE 23505 duplicate')).toBe(
      'Esta operação já foi registrada.'
    );
  });
});
