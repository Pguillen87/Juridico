import { createHash } from 'node:crypto';
import { z } from 'zod';

export const REPORT_SCHEMA_VERSION = 'report-v1' as const;
export const REPORT_STATUSES = [
  'draft',
  'awaiting_review',
  'approved',
  'cancelled',
] as const;
export type ReportStatus = (typeof REPORT_STATUSES)[number];

export const reportEditorialSchema = z
  .object({
    title: z.string().trim().max(240).optional(),
    summary_note: z.string().trim().max(2000).optional(),
    process_notes: z.record(z.string(), z.string().trim().max(1000)).optional(),
    party_notes: z.record(z.string(), z.string().trim().max(1000)).optional(),
    closing_note: z.string().trim().max(2000).optional(),
  })
  .strict()
  .refine((value) => Object.keys(value).length > 0, {
    message: 'Informe ao menos um campo editorial.',
  });

export type ReportEditorial = z.infer<typeof reportEditorialSchema>;

export const reportIdSchema = z.string().uuid();
export const idempotencyKeySchema = z
  .string()
  .regex(/^[A-Za-z0-9._:-]{1,120}$/);

export type ReportVersionRecord = {
  readonly id: string;
  readonly report_id: string;
  readonly office_id: string;
  readonly version_number: number;
  readonly previous_version_id: string | null;
  readonly base_version_id: string | null;
  readonly source_version_id: string | null;
  readonly created_by: string | null;
  readonly creation_kind: 'generated' | 'editorial' | 'restored';
  readonly schema_version: typeof REPORT_SCHEMA_VERSION;
  readonly structured_content: Record<string, unknown>;
  readonly source_manifest: Record<string, unknown>;
  readonly content_hash: string;
  readonly created_at: string;
};

export type ReportSummary = {
  readonly id: string;
  readonly client_id: string;
  readonly period_start_utc: string;
  readonly period_end_utc: string;
  readonly timezone: string;
  readonly status: ReportStatus;
  readonly current_version_id: string | null;
  readonly approved_version_id: string | null;
  readonly approved_hash: string | null;
  readonly approved_by: string | null;
  readonly approved_at: string | null;
  readonly cancelled_at: string | null;
  readonly updated_at: string;
};

function canonicalValue(value: unknown): unknown {
  if (value === null) return null;
  if (typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Valor numérico inválido.');
    return value;
  }
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, canonicalValue(child)])
    );
  }
  throw new Error('Valor não serializável.');
}

export function canonicalizeReportHashInput(value: unknown): string {
  return JSON.stringify(canonicalValue(value));
}

export function reportContentHash(input: {
  readonly schemaVersion: string;
  readonly periodStartUtc: string;
  readonly periodEndUtc: string;
  readonly structuredContent: Record<string, unknown>;
  readonly sourceManifest: Record<string, unknown>;
}): string {
  return createHash('sha256')
    .update(
      canonicalizeReportHashInput({
        schema_version: input.schemaVersion,
        period_start_utc: input.periodStartUtc,
        period_end_utc: input.periodEndUtc,
        structured_content: input.structuredContent,
        source_manifest: input.sourceManifest,
      }),
      'utf8'
    )
    .digest('hex');
}

export function displayReportStatus(status: ReportStatus): string {
  return {
    draft: 'Rascunho',
    awaiting_review: 'Aguardando revisão',
    approved: 'Aprovado',
    cancelled: 'Cancelado',
  }[status];
}

export function displayReportResult(value: string): string {
  return (
    {
      changed: 'Alteração detectada',
      unchanged: 'Sem alteração comprovada',
      not_comparable: 'Não comparável',
      failure: 'Falha',
    }[value] ?? 'Resultado não classificado'
  );
}
