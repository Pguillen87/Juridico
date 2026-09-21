import { describe, expect, it } from 'vitest';
import { parseClientPortfolioRow } from './portfolio';

describe('client portfolio read model', () => {
  it('maps the server-side portfolio contract without exposing technical identifiers', () => {
    const model = parseClientPortfolioRow({
      clientId: '00000000-0000-0000-0000-000000000001',
      clientName: 'Cliente Sintético',
      processCount: 1,
      noveltyCount: 1,
      notUpdatedCount: 0,
      failureCount: 0,
      reviewCount: 0,
      lastConsultedAt: '2026-09-20T12:00:00.000Z',
      lastSourceUpdatedAt: '2026-09-20T11:00:00.000Z',
      processes: [
        {
          processId: '00000000-0000-0000-0000-000000000002',
          cnjNumber: '00000017320238260100',
          tribunal: 'TJSP',
          isPublic: true,
          status: 'active',
          state: 'changed',
          lastConsultedAt: '2026-09-20T12:00:00.000Z',
          sourceUpdatedAt: '2026-09-20T11:00:00.000Z',
          hasNews: true,
          newMovementCount: 1,
          recentMovement: {
            date: '2026-09-20T11:00:00.000Z',
            description: 'Movimentação sintética',
          },
        },
      ],
    });

    expect(model.clientName).toBe('Cliente Sintético');
    expect(model.processes[0].state).toBe('changed');
    expect(model.processes[0].processId).toBe(
      '00000000-0000-0000-0000-000000000002'
    );
  });

  it('rejects a server response with an unknown process state', () => {
    expect(() =>
      parseClientPortfolioRow({
        clientId: '00000000-0000-0000-0000-000000000001',
        clientName: 'Cliente Sintético',
        processCount: 0,
        noveltyCount: 0,
        notUpdatedCount: 0,
        failureCount: 0,
        reviewCount: 0,
        lastConsultedAt: null,
        lastSourceUpdatedAt: null,
        processes: [
          {
            processId: '00000000-0000-0000-0000-000000000002',
            cnjNumber: '00000017320238260100',
            tribunal: 'TJSP',
            isPublic: true,
            status: 'active',
            state: 'technical_internal_state',
            lastConsultedAt: null,
            sourceUpdatedAt: null,
            hasNews: false,
            newMovementCount: 0,
            recentMovement: null,
          },
        ],
      })
    ).toThrow('estado de processo');
  });
});
