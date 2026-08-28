import 'server-only';

import { createAdminClient } from '@/lib/supabase/admin';

type ReportsGeneratorClient = {
  rpc: (
    name: string,
    args: Record<string, unknown>
  ) => Promise<{ data: unknown; error: { message: string } | null }>;
};

export type GeneratedReport = {
  readonly reportId: string;
  readonly versionId: string;
  readonly replayed: boolean;
};

function stringValue(value: unknown, name: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Resposta de geração inválida: ${name}.`);
  }
  return value;
}

export async function generateWeeklyReport(
  input: {
    readonly officeId: string;
    readonly clientId: string;
    readonly periodStartUtc?: string;
    readonly periodEndUtc?: string;
    readonly asOfUtc?: string;
  },
  client: ReportsGeneratorClient = createAdminClient() as unknown as ReportsGeneratorClient
): Promise<GeneratedReport> {
  const { data, error } = await client.rpc('phase12_generate_weekly_report', {
    p_office_id: input.officeId,
    p_client_id: input.clientId,
    p_period_start_utc: input.periodStartUtc ?? null,
    p_period_end_utc: input.periodEndUtc ?? null,
    p_as_of_utc: input.asOfUtc ?? new Date().toISOString(),
  });
  if (error) throw new Error('Não foi possível gerar o relatório semanal.');
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== 'object')
    throw new Error('Resposta de geração inválida.');
  const record = row as Record<string, unknown>;
  return {
    reportId: stringValue(record.report_id, 'report_id'),
    versionId: stringValue(record.version_id, 'version_id'),
    replayed: record.replayed === true,
  };
}
