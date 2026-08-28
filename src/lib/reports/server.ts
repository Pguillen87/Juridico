import 'server-only';

import { redirect } from 'next/navigation';
import { requireAuthenticatedProfile } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import type {
  ReportStatus,
  ReportSummary,
  ReportVersionRecord,
} from './contract';

export async function requireReportAccess() {
  const context = await requireAuthenticatedProfile();
  if (
    context.profile.role !== 'lawyer' &&
    context.profile.role !== 'reviewer'
  ) {
    redirect('/app?error=forbidden');
  }
  return context;
}

export type ReportFilters = {
  readonly clientId?: string;
  readonly status?: ReportStatus;
  readonly periodStart?: string;
  readonly periodEnd?: string;
};

export type ReportProcessRecord = {
  readonly id: string;
  readonly process_id: string;
  readonly content: Record<string, unknown>;
  readonly source_manifest: Record<string, unknown>;
};

export type ReportPartyRecord = {
  readonly id: string;
  readonly party_id: string;
  readonly content: Record<string, unknown>;
  readonly source_manifest: Record<string, unknown>;
};

export type ReportDetail = {
  readonly report: ReportSummary;
  readonly versions: readonly ReportVersionRecord[];
  readonly processes: readonly ReportProcessRecord[];
  readonly parties: readonly ReportPartyRecord[];
};

type QueryResult<T> = Promise<{
  data: T | null;
  error: { message: string } | null;
}>;

type ReportsDb = {
  from: (table: string) => {
    select: (columns: string) => {
      eq: (column: string, value: unknown) => ReportsQuery;
      gte: (column: string, value: unknown) => ReportsQuery;
      lte: (column: string, value: unknown) => ReportsQuery;
      order: (column: string, options: { ascending: boolean }) => ReportsQuery;
    };
  };
  rpc: (name: string, args: Record<string, unknown>) => QueryResult<unknown>;
};

type ReportsQuery = {
  eq: (column: string, value: unknown) => ReportsQuery;
  gte: (column: string, value: unknown) => ReportsQuery;
  lte: (column: string, value: unknown) => ReportsQuery;
  order: (column: string, options: { ascending: boolean }) => ReportsQuery;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function stringValue(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Resposta de relatório inválida: ${field}.`);
  }
  return value;
}

function nullableString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function statusValue(value: unknown): ReportStatus {
  if (
    value === 'draft' ||
    value === 'awaiting_review' ||
    value === 'approved' ||
    value === 'cancelled'
  ) {
    return value;
  }
  throw new Error('Resposta de relatório inválida: status.');
}

function jsonObject(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : {};
}

function reportSummary(row: unknown): ReportSummary {
  if (!isRecord(row)) throw new Error('Resposta de relatório inválida.');
  return {
    id: stringValue(row.id, 'id'),
    client_id: stringValue(row.client_id, 'client_id'),
    period_start_utc: stringValue(row.period_start_utc, 'period_start_utc'),
    period_end_utc: stringValue(row.period_end_utc, 'period_end_utc'),
    timezone: stringValue(row.timezone, 'timezone'),
    status: statusValue(row.status),
    current_version_id: nullableString(row.current_version_id),
    approved_version_id: nullableString(row.approved_version_id),
    approved_hash: nullableString(row.approved_hash),
    approved_by: nullableString(row.approved_by),
    approved_at: nullableString(row.approved_at),
    cancelled_at: nullableString(row.cancelled_at),
    updated_at: stringValue(row.updated_at, 'updated_at'),
  };
}

function reportVersion(row: unknown): ReportVersionRecord {
  if (!isRecord(row)) throw new Error('Resposta de versão inválida.');
  const creationKind = row.creation_kind;
  if (
    creationKind !== 'generated' &&
    creationKind !== 'editorial' &&
    creationKind !== 'restored'
  ) {
    throw new Error('Resposta de versão inválida: creation_kind.');
  }
  if (row.schema_version !== 'report-v1') {
    throw new Error('Versão de schema de relatório não suportada.');
  }
  return {
    id: stringValue(row.id, 'id'),
    report_id: stringValue(row.report_id, 'report_id'),
    office_id: stringValue(row.office_id, 'office_id'),
    version_number: Number(row.version_number),
    previous_version_id: nullableString(row.previous_version_id),
    base_version_id: nullableString(row.base_version_id),
    source_version_id: nullableString(row.source_version_id),
    created_by: nullableString(row.created_by),
    creation_kind: creationKind,
    schema_version: 'report-v1',
    structured_content: jsonObject(row.structured_content),
    source_manifest: jsonObject(row.source_manifest),
    content_hash: stringValue(row.content_hash, 'content_hash'),
    created_at: stringValue(row.created_at, 'created_at'),
  };
}

function processRecord(row: unknown): ReportProcessRecord {
  if (!isRecord(row))
    throw new Error('Resposta de processo de relatório inválida.');
  return {
    id: stringValue(row.id, 'id'),
    process_id: stringValue(row.process_id, 'process_id'),
    content: jsonObject(row.content),
    source_manifest: jsonObject(row.source_manifest),
  };
}

function partyRecord(row: unknown): ReportPartyRecord {
  if (!isRecord(row))
    throw new Error('Resposta de parte de relatório inválida.');
  return {
    id: stringValue(row.id, 'id'),
    party_id: stringValue(row.party_id, 'party_id'),
    content: jsonObject(row.content),
    source_manifest: jsonObject(row.source_manifest),
  };
}

function queryError(error: { message: string } | null): never | void {
  if (error) throw new Error('Não foi possível carregar os relatórios.');
}

export async function listReports(
  filters: ReportFilters = {}
): Promise<readonly ReportSummary[]> {
  const database = (await createClient()) as unknown as ReportsDb;
  let query = database
    .from('weekly_report')
    .select(
      'id,client_id,period_start_utc,period_end_utc,timezone,status,current_version_id,approved_version_id,approved_hash,approved_by,approved_at,cancelled_at,updated_at'
    )
    .order('period_end_utc', { ascending: false });
  if (filters.clientId) query = query.eq('client_id', filters.clientId);
  if (filters.status) query = query.eq('status', filters.status);
  if (filters.periodStart)
    query = query.gte('period_end_utc', filters.periodStart);
  if (filters.periodEnd)
    query = query.lte('period_start_utc', filters.periodEnd);
  const { data, error } = (await query) as unknown as {
    data: unknown[] | null;
    error: { message: string } | null;
  };
  queryError(error);
  return (data ?? []).map(reportSummary);
}

export async function getReportDetail(
  reportId: string
): Promise<ReportDetail | null> {
  const database = (await createClient()) as unknown as ReportsDb;
  const [reportResponse, versionsResponse, processesResponse, partiesResponse] =
    await Promise.all([
      database
        .from('weekly_report')
        .select('*')
        .eq('id', reportId) as unknown as QueryResult<unknown[]>,
      database
        .from('report_version')
        .select('*')
        .eq('report_id', reportId)
        .order('version_number', {
          ascending: false,
        }) as unknown as QueryResult<unknown[]>,
      database
        .from('report_process')
        .select('*')
        .eq('report_id', reportId) as unknown as QueryResult<unknown[]>,
      database
        .from('report_party')
        .select('*')
        .eq('report_id', reportId) as unknown as QueryResult<unknown[]>,
    ]);
  queryError(reportResponse.error);
  queryError(versionsResponse.error);
  queryError(processesResponse.error);
  queryError(partiesResponse.error);
  const firstReport = reportResponse.data?.[0];
  if (!firstReport) return null;
  return {
    report: reportSummary(firstReport),
    versions: (versionsResponse.data ?? []).map(reportVersion),
    processes: (processesResponse.data ?? []).map(processRecord),
    parties: (partiesResponse.data ?? []).map(partyRecord),
  };
}

export async function callReportRpc(
  name: string,
  args: Record<string, unknown>
) {
  const database = (await createClient()) as unknown as ReportsDb;
  const { data, error } = await database.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}
