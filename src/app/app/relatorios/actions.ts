'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';

const idSchema = z.string().uuid();
const keySchema = z.string().regex(/^[A-Za-z0-9._:-]{1,120}$/);
const editorialSchema = z
  .object({
    reportId: idSchema,
    baseVersionId: idSchema,
    idempotencyKey: keySchema,
    title: z.string().trim().max(240).optional(),
    summaryNote: z.string().trim().max(2000).optional(),
    closingNote: z.string().trim().max(2000).optional(),
  })
  .strict()
  .refine(
    (value) => Boolean(value.title || value.summaryNote || value.closingNote),
    { message: 'Informe ao menos um campo editorial.' }
  );

const restoreSchema = z.object({
  reportId: idSchema,
  baseVersionId: idSchema,
  sourceVersionId: idSchema,
  idempotencyKey: keySchema,
});

const reviewSchema = z.object({
  reportId: idSchema,
  versionId: idSchema,
  idempotencyKey: keySchema,
});

const cancelSchema = reviewSchema.extend({
  reasonCode: z.enum([
    'duplicate',
    'incorrect_content',
    'no_longer_required',
    'other',
  ]),
});

export type ReportActionState = {
  readonly success?: boolean;
  readonly message?: string;
  readonly error?: string;
  readonly versionId?: unknown;
};

function safeError(message?: string): string {
  if (message?.includes('permission denied'))
    return 'Você não tem autorização para esta operação.';
  if (message?.includes('stale'))
    return 'A versão mudou. Recarregue o relatório antes de tentar novamente.';
  if (message?.includes('hash mismatch'))
    return 'A versão não pôde ser aprovada porque sua integridade não foi confirmada.';
  if (message?.includes('manual_review_required'))
    return 'A geração exige revisão manual e não criou um rascunho parcial.';
  if (message?.includes('not editable'))
    return 'Este relatório não está em um estado editável.';
  if (message?.includes('not restorable'))
    return 'Este relatório não está em um estado restaurável.';
  if (message?.includes('cannot be cancelled'))
    return 'Este relatório não pode mais ser cancelado.';
  if (message?.includes('invalid')) return 'Os dados informados são inválidos.';
  return 'Não foi possível concluir a operação.';
}

function actionError(error: unknown): ReportActionState {
  return {
    error: safeError(error instanceof Error ? error.message : undefined),
  };
}

export async function createEditorialVersionAction(
  _previousState: ReportActionState | null,
  formData: FormData
): Promise<ReportActionState> {
  let redirectPath: string | null = null;
  let result: ReportActionState = {
    error: 'Não foi possível concluir a operação.',
  };
  try {
    await requirePermission('edit_report_draft', { redirectOnDenied: false });
    const parsed = editorialSchema.safeParse({
      reportId: formData.get('reportId'),
      baseVersionId: formData.get('baseVersionId'),
      idempotencyKey: formData.get('idempotencyKey'),
      title: formData.get('title') || undefined,
      summaryNote: formData.get('summaryNote') || undefined,
      closingNote: formData.get('closingNote') || undefined,
    });
    if (!parsed.success)
      return { error: 'Informe um conteúdo editorial válido.' };
    const db = await createClient();
    const { data, error } = await db.rpc('phase12_create_editorial_version', {
      p_report_id: parsed.data.reportId,
      p_base_version_id: parsed.data.baseVersionId,
      p_editorial: {
        ...(parsed.data.title ? { title: parsed.data.title } : {}),
        ...(parsed.data.summaryNote
          ? { summary_note: parsed.data.summaryNote }
          : {}),
        ...(parsed.data.closingNote
          ? { closing_note: parsed.data.closingNote }
          : {}),
      },
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return actionError(error.message);
    revalidatePath('/app/relatorios');
    revalidatePath(`/app/relatorios/${parsed.data.reportId}`);
    result = {
      success: true,
      message:
        'Nova versão editorial criada. Os fatos técnicos permanecem congelados.',
      versionId: data,
    };
    redirectPath = `/app/relatorios/${parsed.data.reportId}?result=editorial-created`;
  } catch (error) {
    result = actionError(error);
  }
  if (redirectPath) redirect(redirectPath);
  return result;
}

export async function restoreReportVersionAction(
  _previousState: ReportActionState | null,
  formData: FormData
): Promise<ReportActionState> {
  let redirectPath: string | null = null;
  let result: ReportActionState = {
    error: 'Não foi possível concluir a operação.',
  };
  try {
    await requirePermission('edit_report_draft', { redirectOnDenied: false });
    const parsed = restoreSchema.safeParse(
      Object.fromEntries(formData.entries())
    );
    if (!parsed.success)
      return { error: 'A restauração informada é inválida.' };
    const db = await createClient();
    const { data, error } = await db.rpc('phase12_restore_report_version', {
      p_report_id: parsed.data.reportId,
      p_base_version_id: parsed.data.baseVersionId,
      p_source_version_id: parsed.data.sourceVersionId,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return actionError(error.message);
    revalidatePath('/app/relatorios');
    revalidatePath(`/app/relatorios/${parsed.data.reportId}`);
    result = {
      success: true,
      message: 'Conteúdo editorial restaurado em uma nova versão.',
      versionId: data,
    };
    redirectPath = `/app/relatorios/${parsed.data.reportId}?result=editorial-restored`;
  } catch (error) {
    result = actionError(error);
  }
  if (redirectPath) redirect(redirectPath);
  return result;
}

export async function submitReportAction(
  _previousState: ReportActionState | null,
  formData: FormData
): Promise<ReportActionState> {
  let redirectPath: string | null = null;
  let result: ReportActionState = {
    error: 'Não foi possível concluir a operação.',
  };
  try {
    await requirePermission('review_report', { redirectOnDenied: false });
    const parsed = reviewSchema.safeParse(
      Object.fromEntries(formData.entries())
    );
    if (!parsed.success) return { error: 'A submissão informada é inválida.' };
    const db = await createClient();
    const { error } = await db.rpc('phase12_submit_report', {
      p_report_id: parsed.data.reportId,
      p_version_id: parsed.data.versionId,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return actionError(error.message);
    revalidatePath('/app/relatorios');
    revalidatePath(`/app/relatorios/${parsed.data.reportId}`);
    result = { success: true, message: 'Relatório enviado para revisão.' };
    redirectPath = `/app/relatorios/${parsed.data.reportId}?result=submitted`;
  } catch (error) {
    result = actionError(error);
  }
  if (redirectPath) redirect(redirectPath);
  return result;
}

export async function returnReportToDraftAction(
  _previousState: ReportActionState | null,
  formData: FormData
): Promise<ReportActionState> {
  let redirectPath: string | null = null;
  let result: ReportActionState = {
    error: 'Não foi possível concluir a operação.',
  };
  try {
    await requirePermission('review_report', { redirectOnDenied: false });
    const parsed = reviewSchema.safeParse(
      Object.fromEntries(formData.entries())
    );
    if (!parsed.success) return { error: 'O retorno para edição é inválido.' };
    const db = await createClient();
    const { error } = await db.rpc('phase12_return_report_to_draft', {
      p_report_id: parsed.data.reportId,
      p_version_id: parsed.data.versionId,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return actionError(error.message);
    revalidatePath('/app/relatorios');
    revalidatePath(`/app/relatorios/${parsed.data.reportId}`);
    result = { success: true, message: 'Relatório devolvido para edição.' };
    redirectPath = `/app/relatorios/${parsed.data.reportId}?result=returned`;
  } catch (error) {
    result = actionError(error);
  }
  if (redirectPath) redirect(redirectPath);
  return result;
}

export async function approveReportAction(
  _previousState: ReportActionState | null,
  formData: FormData
): Promise<ReportActionState> {
  let redirectPath: string | null = null;
  let result: ReportActionState = {
    error: 'Não foi possível concluir a operação.',
  };
  try {
    await requirePermission('approve_final_report', {
      redirectOnDenied: false,
    });
    const parsed = reviewSchema.safeParse(
      Object.fromEntries(formData.entries())
    );
    if (!parsed.success) return { error: 'A aprovação informada é inválida.' };
    const db = await createClient();
    const { error } = await db.rpc('phase12_approve_report', {
      p_report_id: parsed.data.reportId,
      p_version_id: parsed.data.versionId,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return actionError(error.message);
    revalidatePath('/app/relatorios');
    revalidatePath(`/app/relatorios/${parsed.data.reportId}`);
    result = {
      success: true,
      message:
        'Versão aprovada com hash recalculado. Aprovação não significa envio.',
    };
    redirectPath = `/app/relatorios/${parsed.data.reportId}?result=approved`;
  } catch (error) {
    result = actionError(error);
  }
  if (redirectPath) redirect(redirectPath);
  return result;
}

export async function cancelReportAction(
  _previousState: ReportActionState | null,
  formData: FormData
): Promise<ReportActionState> {
  let redirectPath: string | null = null;
  let result: ReportActionState = {
    error: 'Não foi possível concluir a operação.',
  };
  try {
    await requirePermission('cancel_report', { redirectOnDenied: false });
    const parsed = cancelSchema.safeParse(
      Object.fromEntries(formData.entries())
    );
    if (!parsed.success)
      return { error: 'O cancelamento informado é inválido.' };
    const db = await createClient();
    const { error } = await db.rpc('phase12_cancel_report', {
      p_report_id: parsed.data.reportId,
      p_reason_code: parsed.data.reasonCode,
      p_idempotency_key: parsed.data.idempotencyKey,
    });
    if (error) return actionError(error.message);
    revalidatePath('/app/relatorios');
    revalidatePath(`/app/relatorios/${parsed.data.reportId}`);
    result = {
      success: true,
      message: 'Relatório cancelado. O estado é terminal nesta fase.',
    };
    redirectPath = `/app/relatorios/${parsed.data.reportId}?result=cancelled`;
  } catch (error) {
    result = actionError(error);
  }
  if (redirectPath) redirect(redirectPath);
  return result;
}
