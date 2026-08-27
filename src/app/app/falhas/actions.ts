'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';

const reprocessSchema = z.object({
  incidentId: z.string().uuid(),
  idempotencyKey: z.string().regex(/^[A-Za-z0-9._:-]{1,120}$/),
});

const resolveSchema = z.object({
  incidentId: z.string().uuid(),
  resolutionCode: z.enum([
    'closed_by_operator',
    'not_reproducible',
    'manual_review_complete',
    'reprocessed',
  ]),
  resolutionNote: z.string().trim().min(1).max(2000),
  idempotencyKey: z.string().regex(/^[A-Za-z0-9._:-]{1,120}$/),
});

const assignSchema = z.object({
  incidentId: z.string().uuid(),
  assigneeUserId: z.union([z.string().uuid(), z.literal('')]),
  idempotencyKey: z.string().regex(/^[A-Za-z0-9._:-]{1,120}$/),
});

const noteSchema = z.object({
  incidentId: z.string().uuid(),
  note: z.string().trim().min(1).max(2000),
  idempotencyKey: z.string().regex(/^[A-Za-z0-9._:-]{1,120}$/),
});

function safeError(message?: string) {
  if (message?.includes('permission denied'))
    return 'Você não tem autorização para esta operação.';
  if (message?.includes('not found'))
    return 'A falha não foi encontrada no seu escritório.';
  if (message?.includes('eligible'))
    return 'A falha não está elegível para esta operação.';
  if (message?.includes('invalid')) return 'Os dados informados são inválidos.';
  return 'Não foi possível concluir a operação.';
}

export async function requestFailureReprocessAction(formData: FormData) {
  try {
    await requirePermission('manual_reprocess', { redirectOnDenied: false });
    const parsed = reprocessSchema.safeParse({
      incidentId: formData.get('incidentId'),
      idempotencyKey: formData.get('idempotencyKey'),
    });
    if (!parsed.success)
      return { error: 'Identificador de reprocessamento inválido.' };
    const supabase = await createClient();
    const { data, error } = await supabase.rpc(
      'phase11_request_failure_reprocess',
      {
        p_incident_id: parsed.data.incidentId,
        p_idempotency_key: parsed.data.idempotencyKey,
      }
    );
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/falhas');
    revalidatePath(`/app/falhas/${parsed.data.incidentId}`);
    return { success: true, jobId: data };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function resolveFailureAction(formData: FormData) {
  try {
    await requirePermission('handle_failures', { redirectOnDenied: false });
    const parsed = resolveSchema.safeParse({
      incidentId: formData.get('incidentId'),
      resolutionCode: formData.get('resolutionCode'),
      resolutionNote: formData.get('resolutionNote'),
      idempotencyKey: formData.get('idempotencyKey'),
    });
    if (!parsed.success)
      return { error: 'Informe motivo e observação da resolução.' };
    const supabase = await createClient();
    const { error } = await supabase.rpc('phase11_resolve_failure_incident', {
      p_incident_id: parsed.data.incidentId,
      p_resolution_code: parsed.data.resolutionCode,
      p_resolution_note: parsed.data.resolutionNote,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/falhas');
    revalidatePath(`/app/falhas/${parsed.data.incidentId}`);
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function assignFailureAction(formData: FormData) {
  try {
    await requirePermission('handle_failures', { redirectOnDenied: false });
    const parsed = assignSchema.safeParse({
      incidentId: formData.get('incidentId'),
      assigneeUserId: formData.get('assigneeUserId'),
      idempotencyKey: formData.get('idempotencyKey'),
    });
    if (!parsed.success) return { error: 'Atribuição inválida.' };
    const supabase = await createClient();
    const { error } = await supabase.rpc('phase11_assign_failure_incident', {
      p_incident_id: parsed.data.incidentId,
      p_assignee_user_id: parsed.data.assigneeUserId || null,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/falhas');
    revalidatePath(`/app/falhas/${parsed.data.incidentId}`);
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function addFailureNoteAction(formData: FormData) {
  try {
    await requirePermission('handle_failures', { redirectOnDenied: false });
    const parsed = noteSchema.safeParse({
      incidentId: formData.get('incidentId'),
      note: formData.get('note'),
      idempotencyKey: formData.get('idempotencyKey'),
    });
    if (!parsed.success) return { error: 'Informe uma observação válida.' };
    const supabase = await createClient();
    const { error } = await supabase.rpc('phase11_add_failure_note', {
      p_incident_id: parsed.data.incidentId,
      p_note: parsed.data.note,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/falhas');
    revalidatePath(`/app/falhas/${parsed.data.incidentId}`);
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}
