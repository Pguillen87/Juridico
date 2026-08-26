import type { ManualObservationInput } from './adapters/manual';

export const SYNTHETIC_MANUAL_OBSERVATION: ManualObservationInput = {
  processRef: 'synthetic-process-001',
  evidenceRef: 'synthetic-evidence-001',
  observedAt: '2026-01-01T00:01:00.000Z',
  tribunal: 'tribunal-sintetico',
  system: 'sistema-sintetico',
  movements: [
    {
      movementRef: 'synthetic-movement-001',
      date: '2026-01-01',
      description: 'Movimentação sintética para teste de contrato.',
    },
  ],
};
