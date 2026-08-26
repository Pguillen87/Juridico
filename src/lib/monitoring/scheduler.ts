import 'server-only';

import { createAdminClient } from '@/lib/supabase/admin';
import type { MonitoringRpcClient } from './worker';

export type SchedulerTickResult = {
  readonly scheduledAt: string;
  readonly createdJobs: number;
};

export async function runMonitoringSchedulerTick(
  asOf = new Date(),
  options: {
    readonly toleranceSeconds?: number;
    readonly client?: MonitoringRpcClient;
  } = {}
): Promise<SchedulerTickResult> {
  if (Number.isNaN(asOf.getTime())) {
    throw new Error('Instante de scheduler inválido.');
  }
  const toleranceSeconds = options.toleranceSeconds ?? 300;
  if (
    !Number.isInteger(toleranceSeconds) ||
    toleranceSeconds < 0 ||
    toleranceSeconds > 900
  ) {
    throw new Error('Tolerância de janela inválida.');
  }
  const client =
    options.client ?? (createAdminClient() as unknown as MonitoringRpcClient);
  const { data, error } = await client.rpc('phase9_scheduler_tick', {
    p_as_of: asOf.toISOString(),
    p_window_tolerance_seconds: toleranceSeconds,
  });
  if (
    error ||
    typeof data !== 'number' ||
    !Number.isInteger(data) ||
    data < 0
  ) {
    throw new Error('Não foi possível executar a janela de scheduler.');
  }
  return { scheduledAt: asOf.toISOString(), createdJobs: data };
}
