import { describe, expect, it } from 'vitest';

import { snapshotHash } from '@/lib/monitoring/snapshots';
import {
  COMPARISON_VERSION_V1,
  ComparisonInputError,
  UnknownComparisonVersionError,
  canonicalizeComparison,
  compareSnapshots,
} from './comparator';
import type { ComparisonSnapshot } from './comparator';

const completeData = {
  processRef: 'synthetic-process-ref',
  tribunal: 'TJ-SYNTHETIC',
  system: 'synthetic-system',
  movements: [
    {
      movementRef: 'movement-001',
      date: '2026-01-01T10:00:00.000Z',
      description: 'Movimentação sintética.',
      missingFields: [],
    },
  ],
  parties: [
    {
      partyRef: 'party-001',
      role: 'plaintiff',
      missingFields: [],
    },
  ],
} as const;

function makeSnapshot(
  overrides: Partial<ComparisonSnapshot> = {},
  data: ComparisonSnapshot['normalizedData'] = completeData
): ComparisonSnapshot {
  return {
    id: overrides.id ?? 'snapshot-001',
    officeId: overrides.officeId ?? 'office-001',
    processId: overrides.processId ?? 'process-001',
    providerId: overrides.providerId ?? 'datajud_sandbox',
    source: overrides.source ?? 'datajud',
    normalizerVersion: overrides.normalizerVersion ?? '1.0.0',
    normalizedData: overrides.normalizedData ?? data,
    missingFields: overrides.missingFields ?? [],
    snapshotHash: overrides.snapshotHash ?? snapshotHash(data),
    createdAt: overrides.createdAt ?? '2026-01-01T11:00:00.000Z',
  };
}

describe('comparison core', () => {
  it('mantém uma versão ativa interna e rejeita versões arbitrárias', () => {
    expect(COMPARISON_VERSION_V1).toBe('comparison-v1');
    expect(() => compareSnapshots(null, makeSnapshot(), '123')).toThrow(
      UnknownComparisonVersionError
    );
    expect(() => compareSnapshots(null, makeSnapshot(), 'custom')).toThrow(
      UnknownComparisonVersionError
    );
  });

  it('produz not_comparable para o primeiro snapshot', () => {
    const result = compareSnapshots(null, makeSnapshot());
    expect(result.result).toBe('not_comparable');
    expect(result.reasonCode).toBe('first_snapshot');
    expect(result.changedFields).toEqual([]);
  });

  it('produz unchanged e hash determinístico para dados semanticamente iguais', () => {
    const previous = makeSnapshot({ id: 'snapshot-previous' });
    const current = makeSnapshot(
      {
        id: 'snapshot-current',
        createdAt: '2026-01-02T11:00:00.000Z',
      },
      {
        ...completeData,
        movements: [...completeData.movements].reverse(),
        parties: [...completeData.parties].reverse(),
      }
    );
    const result = compareSnapshots(previous, current);
    const replay = compareSnapshots(previous, current);
    expect(result.result).toBe('unchanged');
    expect(result.normalizedDiff.entries).toEqual([]);
    expect(result.comparisonHash).toBe(replay.comparisonHash);
  });

  it('produz changed para movimento adicionado, removido e atualizado', () => {
    const previous = makeSnapshot({ id: 'snapshot-previous' });
    const currentData = {
      ...completeData,
      movements: [
        {
          movementRef: 'movement-001',
          date: '2026-01-01T10:00:00.000Z',
          description: 'Movimentação atualizada.',
          missingFields: [],
        },
        {
          movementRef: 'movement-002',
          date: '2026-01-02T10:00:00.000Z',
          description: 'Movimentação nova.',
          missingFields: [],
        },
      ],
    } as const;
    const result = compareSnapshots(
      previous,
      makeSnapshot(
        {
          id: 'snapshot-current',
          createdAt: '2026-01-02T11:00:00.000Z',
        },
        currentData
      )
    );
    expect(result.result).toBe('changed');
    expect(result.normalizedDiff.entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          path: '/movements/by-ref/movement-001/description',
          changeType: 'movement_updated',
        }),
        expect.objectContaining({
          path: '/movements/by-ref/movement-002',
          changeType: 'movement_added',
        }),
      ])
    );
  });

  it('compara parties por partyRef e não por nome', () => {
    const previous = makeSnapshot({ id: 'snapshot-previous' });
    const currentData = {
      ...completeData,
      parties: [
        {
          partyRef: 'party-001',
          role: 'defendant',
          missingFields: [],
        },
      ],
    } as const;
    const result = compareSnapshots(
      previous,
      makeSnapshot(
        { id: 'snapshot-current', createdAt: '2026-01-02T11:00:00.000Z' },
        currentData
      )
    );
    expect(result.result).toBe('changed');
    expect(result.changedFields).toContain('/parties/by-ref/party-001/role');
  });

  it('retorna not_comparable quando há incompletude ou versões incompatíveis', () => {
    const previous = makeSnapshot({ id: 'snapshot-previous' });
    const currentDate = '2026-01-02T11:00:00.000Z';
    expect(
      compareSnapshots(
        previous,
        makeSnapshot(
          {
            id: 'snapshot-current',
            createdAt: currentDate,
            missingFields: ['system'],
          },
          {
            processRef: completeData.processRef,
            tribunal: completeData.tribunal,
            movements: completeData.movements,
            parties: completeData.parties,
          }
        )
      ).reasonCode
    ).toBe('required_field_missing');
    expect(
      compareSnapshots(
        previous,
        makeSnapshot({
          id: 'snapshot-current',
          createdAt: currentDate,
          normalizerVersion: '2.0.0',
        })
      ).reasonCode
    ).toBe('normalizer_incompatible');
    expect(
      compareSnapshots(
        previous,
        makeSnapshot({
          id: 'snapshot-current',
          createdAt: currentDate,
          source: 'manual',
        })
      ).reasonCode
    ).toBe('source_incompatible');
  });

  it('rejeita snapshots de outro tenant, snapshot futuro e hash divergente', () => {
    const previous = makeSnapshot({ id: 'snapshot-previous' });
    expect(() =>
      compareSnapshots(
        previous,
        makeSnapshot({
          id: 'snapshot-current',
          createdAt: '2026-01-02T11:00:00.000Z',
          officeId: 'office-002',
        })
      )
    ).toThrow(ComparisonInputError);
    expect(() =>
      compareSnapshots(
        previous,
        makeSnapshot({
          id: 'snapshot-current',
          createdAt: '2025-12-31T11:00:00.000Z',
        })
      )
    ).toThrow(ComparisonInputError);
    expect(() =>
      compareSnapshots(
        previous,
        makeSnapshot({
          id: 'snapshot-current',
          createdAt: '2026-01-02T11:00:00.000Z',
          snapshotHash: 'x'.repeat(64),
        })
      )
    ).toThrow(ComparisonInputError);
  });

  it('canonicaliza objetos independentemente da ordem de chaves', () => {
    expect(canonicalizeComparison({ b: 2, a: { d: 'x', c: true } })).toBe(
      canonicalizeComparison({ a: { c: true, d: 'x' }, b: 2 })
    );
  });
});
