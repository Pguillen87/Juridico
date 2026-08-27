import { describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));

import { snapshotHash } from '@/lib/monitoring/snapshots';
import type { NormalizedProcessObservation } from '@/lib/providers/contract';
import {
  compareAndPersistSnapshot,
  type ComparisonRpcClient,
} from './persistence';

const observationData: NormalizedProcessObservation = {
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
};

describe('compareAndPersistSnapshot', () => {
  it('aceita a resposta RPC realista com o diff persistido', async () => {
    const currentSnapshotId = '91000000-0000-4000-b000-000000000001';
    const rpc = vi
      .fn<ComparisonRpcClient['rpc']>()
      .mockResolvedValueOnce({
        data: [
          {
            snapshot_role: 'current',
            id: currentSnapshotId,
            office_id: '91000000-0000-4000-9000-000000000001',
            process_id: '91000000-0000-4000-c000-000000000001',
            provider_id: 'datajud_sandbox',
            source: 'datajud',
            normalizer_version: '1.0.0',
            normalized_data: observationData,
            missing_fields: [],
            snapshot_hash: snapshotHash(observationData),
            created_at: '2026-01-01T11:00:00.000Z',
          },
        ],
        error: null,
      })
      .mockResolvedValueOnce({
        data: [
          {
            comparison_id: '91000000-0000-4000-1100-000000000001',
            detected_change_id: null,
            result: 'not_comparable',
            reason_code: 'first_snapshot',
            comparison_hash: 'b'.repeat(64),
            changed_fields: [],
            normalized_diff: { entries: [] },
            replayed: false,
          },
        ],
        error: null,
      });
    const client: ComparisonRpcClient = { rpc };

    const result = await compareAndPersistSnapshot(currentSnapshotId, client);

    expect(result).toMatchObject({
      comparisonVersion: 'comparison-v1',
      comparisonId: '91000000-0000-4000-1100-000000000001',
      detectedChangeId: null,
      result: 'not_comparable',
      reasonCode: 'first_snapshot',
      changedFields: [],
      normalizedDiff: { entries: [] },
      comparisonHash: 'b'.repeat(64),
      replayed: false,
    });
    expect(rpc).toHaveBeenLastCalledWith('phase10_compare_process_snapshot', {
      p_current_snapshot_id: currentSnapshotId,
      p_comparison_version: 'comparison-v1',
      p_result: 'not_comparable',
      p_reason_code: 'first_snapshot',
      p_changed_fields: [],
      p_normalized_diff: { entries: [] },
    });
  });
});
