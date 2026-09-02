'use server';

import { createHash, randomUUID } from 'node:crypto';
import { z } from 'zod';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';
import { createPlaywrightPdfRenderer } from '@/lib/reports/pdf-renderer';
import { getReportDetail } from '@/lib/reports/server';
import { FakeEmailProvider } from '@/lib/delivery/email-provider';
import type { ReportActionState } from './actions';

/**
 * F13 RPCs are intentionally invoked through a narrow adapter. The generated
 * Supabase schema predates F13 and therefore has no F13 Functions entries;
 * this cast is limited to the typed RPC boundary (no table access).
 */
type F13RpcClient = {
  rpc(
    name: string,
    args: Record<string, unknown>
  ): Promise<{ data: unknown; error: { message: string } | null }>;
  storage: {
    from(bucket: string): {
      upload(
        path: string,
        body: Uint8Array,
        options?: Record<string, unknown>
      ): Promise<{ error: { message: string } | null }>;
      download(
        path: string
      ): Promise<{ data: Blob | null; error: { message: string } | null }>;
    };
  };
};

type ActionState = {
  readonly success?: boolean;
  readonly error?: string;
  readonly message?: string;
  readonly status?: string;
  readonly contactId?: unknown;
  readonly artifactId?: unknown;
  readonly deliveryId?: unknown;
};

const uuid = z.string().uuid();
const key = z.string().trim().min(1).max(240);
const subject = z.string().trim().min(1).max(240);
const reason = z.string().trim().min(1).max(500);
const contactSchema = z
  .object({
    clientId: uuid,
    email: z.string().trim().email().max(320),
    displayName: z.string().trim().min(1).max(240),
  })
  .strict();
const generateSchema = z
  .object({
    reportId: uuid,
    reportVersionId: uuid,
    approvedHash: z.string().regex(/^[a-f0-9]{64}$/),
  })
  .strict();
const sendSchema = z
  .object({
    reportId: uuid,
    reportVersionId: uuid,
    artifactId: uuid,
    clientContactId: uuid,
    subject,
    idempotencyKey: key,
    reason: reason.optional(),
  })
  .strict();
const retrySchema = z
  .object({ deliveryId: uuid, idempotencyKey: key })
  .strict();
const reconcileSchema = z.object({ deliveryId: uuid, reason }).strict();
const resendSchema = z
  .object({ deliveryId: uuid, idempotencyKey: key, reason })
  .strict();
const executeSchema = z.object({ deliveryId: uuid }).strict();

function values(formData: FormData): Record<string, unknown> {
  return Object.fromEntries(formData.entries());
}
function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
function reportHtml(
  detail: NonNullable<Awaited<ReturnType<typeof getReportDetail>>>,
  versionId: string
): string {
  const version = detail.versions.find((item) => item.id === versionId);
  if (
    !version ||
    detail.report.status !== 'approved' ||
    detail.report.approved_version_id !== versionId ||
    detail.report.approved_hash !== version.content_hash
  )
    throw new Error('report is not approved');
  const content = escapeHtml(JSON.stringify(version.structured_content));
  return `<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:Arial,sans-serif;margin:32px;color:#0f172a}h1{font-size:22px}pre{white-space:pre-wrap;font-size:11px}</style></head><body><h1>Relatório semanal</h1><p>Versão aprovada: ${escapeHtml(version.id)}</p><p>Hash de conteúdo: ${escapeHtml(version.content_hash)}</p><pre>${content}</pre></body></html>`;
}
function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message.toLowerCase() : '';
  if (message.includes('permission denied') || message.includes('forbidden'))
    return 'Você não tem autorização para esta operação.';
  if (message.includes('invalid') || message.includes('required'))
    return 'Os dados informados são inválidos.';
  if (message.includes('unknown') || message.includes('reconciliation'))
    return 'A entrega precisa de verificação do provedor falso local.';
  if (message.includes('retry'))
    return 'A entrega não pode ser repetida neste momento.';
  return 'Não foi possível concluir a operação.';
}
async function lawyer(
  permission: 'generate_final_pdf' | 'authorize_send'
): Promise<void> {
  await requirePermission(permission, { redirectOnDenied: false });
}
async function rpc(
  name: string,
  args: Record<string, unknown>
): Promise<unknown> {
  const client = (await createClient()) as unknown as F13RpcClient;
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}

export async function createClientContactAction(
  formData: FormData
): Promise<ActionState> {
  try {
    await lawyer('authorize_send');
    const parsed = contactSchema.safeParse(values(formData));
    if (!parsed.success) return { error: 'Os dados do contato são inválidos.' };
    const data = await rpc('phase13_create_client_contact', {
      p_client_id: parsed.data.clientId,
      p_email: parsed.data.email.toLowerCase(),
      p_display_name: parsed.data.displayName,
    });
    return { success: true, contactId: data };
  } catch (error) {
    return { error: safeError(error) };
  }
}

export async function confirmClientContactAction(
  formData: FormData
): Promise<ActionState> {
  return contactMutation(
    formData,
    'phase13_confirm_client_contact',
    'contactId',
    'p_contact_id'
  );
}
export async function deactivateClientContactAction(
  formData: FormData
): Promise<ActionState> {
  return contactMutation(
    formData,
    'phase13_deactivate_client_contact',
    'contactId',
    'p_contact_id'
  );
}
async function contactMutation(
  formData: FormData,
  name: string,
  field: string,
  parameter: string
): Promise<ActionState> {
  try {
    await lawyer('authorize_send');
    const parsed = z
      .object({ [field]: uuid })
      .strict()
      .safeParse(values(formData));
    if (!parsed.success) return { error: 'Os dados do contato são inválidos.' };
    await rpc(name, { [parameter]: parsed.data[field] });
    return { success: true };
  } catch (error) {
    return { error: safeError(error) };
  }
}

export async function generateFinalPdfAction(
  formData: FormData
): Promise<ActionState> {
  try {
    await lawyer('generate_final_pdf');
    const parsed = generateSchema.safeParse(values(formData));
    if (!parsed.success) return { error: 'Os dados do PDF são inválidos.' };
    const detail = await getReportDetail(parsed.data.reportId);
    if (!detail) return { error: 'Relatório não encontrado.' };
    if (detail.report.approved_hash !== parsed.data.approvedHash)
      return { error: 'A versão aprovada mudou. Recarregue o relatório.' };
    const html = reportHtml(detail, parsed.data.reportVersionId);
    const renderer = await createPlaywrightPdfRenderer();
    const artifact = await renderer.render({
      reportVersionId: parsed.data.reportVersionId,
      approvedHash: parsed.data.approvedHash,
      html,
    });
    const artifactPathId = randomUUID();
    const path = `${parsed.data.reportId}/${parsed.data.reportVersionId}/${artifactPathId}.pdf`;
    const privateStorageUri = `private://private-reports/${path}`;
    const upload = await createAdminClient()
      .storage.from('private-reports')
      .upload(path, artifact.bytes, {
        contentType: 'application/pdf',
        upsert: false,
      });
    if (upload.error) throw new Error(upload.error.message);
    const data = await rpc('phase13_generate_final_pdf', {
      p_report_id: parsed.data.reportId,
      p_report_version_id: parsed.data.reportVersionId,
      p_approved_hash: parsed.data.approvedHash,
      p_file_hash: artifact.artifactSha256,
      p_generation_fingerprint: createHash('sha256')
        .update(
          `report-pdf:v1:${parsed.data.reportId}:${parsed.data.reportVersionId}:${parsed.data.approvedHash}`
        )
        .digest('hex'),
      p_private_storage_uri: privateStorageUri,
      p_byte_size: artifact.bytes.byteLength,
    });
    return { success: true, artifactId: data };
  } catch (error) {
    return { error: safeError(error) };
  }
}

export async function executeFakeDeliveryAction(
  formData: FormData
): Promise<ActionState> {
  let claimedAttempt = 0;
  let claimedDeliveryId: string | null = null;
  try {
    await lawyer('authorize_send');
    const parsed = executeSchema.safeParse(values(formData));
    if (!parsed.success) return { error: 'Os dados da entrega são inválidos.' };
    const delivery = await rpc('phase13_get_delivery_for_send', {
      p_delivery_id: parsed.data.deliveryId,
    });
    const row = Array.isArray(delivery)
      ? (delivery[0] as
          | {
              delivery_id: string;
              attempt_number: number;
              recipient: string;
              subject: string;
              artifact_hash: string;
              storage_bucket: string;
              storage_object_key: string;
            }
          | undefined)
      : undefined;
    if (!row) return { error: 'A entrega não está disponível para execução.' };
    const claim = await (createAdminClient() as unknown as F13RpcClient).rpc(
      'phase13_claim_delivery_attempt',
      { p_delivery_id: row.delivery_id }
    );
    if (claim.error) throw new Error(claim.error.message);
    claimedDeliveryId = row.delivery_id;
    claimedAttempt = row.attempt_number;
    const artifact = await createAdminClient()
      .storage.from(row.storage_bucket)
      .download(row.storage_object_key);
    if (artifact.error || !artifact.data)
      throw new Error('O artefato privado não está disponível.');
    const bytes = new Uint8Array(await artifact.data.arrayBuffer());
    const downloadedHash = createHash('sha256').update(bytes).digest('hex');
    if (
      downloadedHash !== row.artifact_hash ||
      Buffer.from(bytes).subarray(0, 5).toString() !== '%PDF-'
    )
      throw new Error('Integridade do artefato privado não confirmada.');
    const result = await new FakeEmailProvider({
      outcome: FakeEmailProvider.outcomeForDelivery(row.delivery_id),
    }).send({
      idempotencyKey: `${row.delivery_id}:${row.attempt_number}`,
      to: row.recipient,
      subject: row.subject,
      text: 'Relatório semanal aprovado.',
      artifact: { filename: 'report.pdf', bytes, sha256: row.artifact_hash },
    });
    const recorded = await (createAdminClient() as unknown as F13RpcClient).rpc(
      'phase13_record_delivery_attempt',
      {
        p_delivery_id: row.delivery_id,
        p_attempt_number: row.attempt_number,
        p_outcome:
          result.status === 'retryable_failure'
            ? 'retry_available'
            : result.status === 'terminal_failure'
              ? 'failed'
              : result.status,
        p_provider_response_sanitized: {
          provider_message_code: result.status,
          accepted: result.status === 'delivered',
        },
      }
    );
    if (recorded.error) throw new Error(recorded.error.message);
    const status =
      result.status === 'retryable_failure'
        ? 'retry_available'
        : result.status === 'terminal_failure'
          ? 'failed'
          : result.status;
    return { success: true, deliveryId: row.delivery_id, status };
  } catch (error) {
    if (claimedDeliveryId && claimedAttempt > 0) {
      await (createAdminClient() as unknown as F13RpcClient).rpc(
        'phase13_record_delivery_attempt',
        {
          p_delivery_id: claimedDeliveryId,
          p_attempt_number: claimedAttempt,
          p_outcome: 'failed',
          p_provider_response_sanitized: {
            provider_message_code: 'local_execution_failed',
            accepted: false,
          },
        }
      );
    }
    return { error: safeError(error) };
  }
}

export async function authorizeSendAction(
  formData: FormData
): Promise<ActionState> {
  try {
    await lawyer('authorize_send');
    const parsed = sendSchema.safeParse(values(formData));
    if (!parsed.success) return { error: 'Os dados do envio são inválidos.' };
    const data = await rpc('phase13_authorize_send', {
      p_report_id: parsed.data.reportId,
      p_report_version_id: parsed.data.reportVersionId,
      p_artifact_id: parsed.data.artifactId,
      p_client_contact_id: parsed.data.clientContactId,
      p_subject: parsed.data.subject,
      p_idempotency_key: parsed.data.idempotencyKey,
      p_reason: parsed.data.reason ?? null,
    });
    return { success: true, deliveryId: data };
  } catch (error) {
    return { error: safeError(error) };
  }
}
export async function retryDeliveryAction(
  formData: FormData
): Promise<ActionState> {
  return deliveryAction(
    formData,
    retrySchema,
    'phase13_retry_delivery',
    (v) => ({
      p_delivery_id: v.deliveryId,
      p_idempotency_key: v.idempotencyKey,
    })
  );
}
export async function reconcileUnknownDeliveryAction(
  formData: FormData
): Promise<ActionState> {
  try {
    await lawyer('authorize_send');
    const parsed = reconcileSchema.safeParse(values(formData));
    if (!parsed.success)
      return { error: 'Os dados da reconciliação são inválidos.' };
    const evidence = FakeEmailProvider.reconciliationForReference(
      parsed.data.deliveryId
    );
    const result = await (createAdminClient() as unknown as F13RpcClient).rpc(
      'phase13_reconcile_unknown_delivery_with_evidence',
      {
        p_delivery_id: parsed.data.deliveryId,
        p_evidence: evidence,
        p_reason: parsed.data.reason,
      }
    );
    if (result.error) throw new Error(result.error.message);
    return { success: true, status: String(result.data ?? evidence) };
  } catch (error) {
    return { error: safeError(error) };
  }
}
export async function resendDeliveryAction(
  formData: FormData
): Promise<ActionState> {
  return deliveryAction(
    formData,
    resendSchema,
    'phase13_resend_delivery',
    (v) => ({
      p_delivery_id: v.deliveryId,
      p_idempotency_key: v.idempotencyKey,
      p_reason: v.reason,
    })
  );
}
async function deliveryAction<T extends z.ZodTypeAny>(
  formData: FormData,
  schema: T,
  name: string,
  args: (value: z.infer<T>) => Record<string, unknown>
): Promise<ActionState> {
  try {
    await lawyer('authorize_send');
    const parsed = schema.safeParse(values(formData));
    if (!parsed.success)
      return {
        error: name.includes('reconcile')
          ? 'Os dados da reconciliação são inválidos.'
          : 'Os dados da entrega são inválidos.',
      };
    const data = await rpc(name, args(parsed.data));
    return {
      success: true,
      ...(name.includes('resend') || name.includes('authorize')
        ? { deliveryId: data }
        : {}),
    };
  } catch (error) {
    return { error: safeError(error) };
  }
}

export async function generateFinalPdfReportAction(
  _previousState: ReportActionState | null,
  formData: FormData
): Promise<ReportActionState> {
  const result = await generateFinalPdfAction(formData);
  return {
    success: result.success,
    error: result.error,
    message: result.message,
    versionId: result.artifactId,
  };
}
