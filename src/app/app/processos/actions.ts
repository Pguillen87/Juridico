'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import type { Json } from '@/types/database.types';
import {
  parseCsvFile,
  CSV_PARSER_VERSION,
  type ParsedCsv,
} from '@/lib/processes/csv';
import { normalizeName } from '@/lib/processes/names';
import { getDataJudConfiguration } from '@/lib/providers/datajud-config-core';
import {
  getClientPortfolioProcessDetail,
  getClientPortfolioRefreshProgress,
  type ClientPortfolioProcessDetail,
  type ClientPortfolioRefreshProgress,
} from '@/lib/clients/portfolio';

const processSchema = z.object({
  clientId: z.string().uuid(),
  cnj: z.string().min(1),
  tribunal: z.string().trim().min(2).max(200),
  system: z.string().trim().max(120).optional(),
  isPublic: z.enum(['public', 'private']),
});

const monitoringStatusSchema = z.object({
  processId: z.string().uuid(),
  status: z.enum(['paused', 'active']),
});

const relationSchema = z.object({
  processId: z.string().uuid(),
  partyId: z.string().uuid(),
  role: z.enum([
    'client',
    'plaintiff',
    'defendant',
    'representative',
    'interested_party',
    'other',
  ]),
  notes: z.string().max(1000).optional(),
});

function safeError(message?: string) {
  if (message?.includes('permission denied'))
    return 'Você não tem autorização para esta operação.';
  if (message?.includes('duplicate') || message?.includes('23505'))
    return 'Já existe um registro ativo equivalente.';
  if (message?.includes('CNJ') || message?.includes('cnj')) return message;
  if (message?.includes('not found'))
    return 'O registro não foi encontrado no seu escritório.';
  if (message?.includes('expired') || message?.includes('unavailable'))
    return 'A prévia expirou ou já não está disponível. Gere uma nova prévia.';
  if (message?.includes('invalid')) return 'Os dados informados são inválidos.';
  return 'Não foi possível concluir a operação.';
}

export async function createProcessAction(formData: FormData) {
  try {
    await requirePermission('create_process', { redirectOnDenied: false });
    const parsed = processSchema.safeParse({
      clientId: formData.get('clientId'),
      cnj: formData.get('cnj'),
      tribunal: formData.get('tribunal'),
      system: formData.get('system') || undefined,
      isPublic: formData.get('isPublic'),
    });
    if (!parsed.success)
      return { error: 'Informe cliente, CNJ, tribunal e publicidade válidos.' };
    const supabase = await createClient();
    const { data, error } = await supabase.rpc('create_legal_process', {
      p_client_id: parsed.data.clientId,
      p_cnj_number: parsed.data.cnj,
      p_tribunal: parsed.data.tribunal,
      p_system: parsed.data.system ?? null,
      p_is_public: parsed.data.isPublic === 'public',
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app');
    revalidatePath('/app/clientes');
    revalidatePath('/app/processos');
    return { success: true, processId: data };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function setProcessMonitoringStatusAction(formData: FormData) {
  try {
    await requirePermission('manage_monitoring', { redirectOnDenied: false });
    const parsed = monitoringStatusSchema.safeParse({
      processId: formData.get('processId'),
      status: formData.get('status'),
    });
    if (!parsed.success)
      return {
        error: 'Informe um processo e um status de monitoramento válidos.',
      };
    const supabase = await createClient();
    const { error } = await supabase.rpc(
      'phase9_set_process_monitoring_status',
      {
        p_process_id: parsed.data.processId,
        p_status: parsed.data.status,
      }
    );
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/processos');
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

const refreshSchema = z.object({
  processId: z.string().uuid(),
});

const portfolioRefreshSchema = z.object({
  clientId: z.string().uuid(),
});

const selectedProcessesRefreshSchema = z
  .array(z.string().uuid())
  .min(1)
  .max(200);

export type PortfolioRefreshActionResult =
  | {
      success: true;
      state: 'queued' | 'already_running';
      eligibleCount: number;
      skippedCount: number;
    }
  | {
      success: false;
      state: 'not_configured' | 'permission_denied' | 'technical_failure';
      message: string;
    };

export type PortfolioProgressActionResult =
  | { success: true; progress: ClientPortfolioRefreshProgress | null }
  | { success: false; message: string };

export type PortfolioBatchRunActionResult =
  | { success: true; progress: ClientPortfolioRefreshProgress | null }
  | { success: false; message: string };

export type PortfolioProcessDetailActionResult =
  | { success: true; detail: ClientPortfolioProcessDetail | null }
  | { success: false; message: string };

export async function requestProcessRefreshAction(formData: FormData) {
  try {
    await requirePermission('manage_monitoring', {
      redirectOnDenied: false,
    });
    const parsed = refreshSchema.safeParse({
      processId: formData.get('processId'),
    });
    if (!parsed.success) {
      return { error: 'Informe um processo válido para atualização.' };
    }
    const supabase = await createClient();
    const { data, error } = await supabase.rpc(
      'realignment1_request_process_refresh',
      {
        p_process_id: parsed.data.processId,
      }
    );
    if (error) return { error: safeError(error.message) };

    const job = Array.isArray(data) ? data[0] : data;
    if (
      job?.job_id &&
      (job.status === 'pending' || job.status === 'retry_scheduled')
    ) {
      try {
        const { runMonitoringWorkerOnce } =
          await import('@/lib/monitoring/worker');
        const workerResult = await runMonitoringWorkerOnce({
          targetJobId: job.job_id,
        });
        if (workerResult.status === 'stale_or_rejected') {
          return { error: 'Não foi possível concluir a consulta.' };
        }
      } catch (workerErr) {
        console.error(
          'Falha ao executar worker síncrono para o job alvo:',
          workerErr
        );
        return { error: 'Não foi possível concluir a consulta.' };
      }
    }

    revalidatePath('/app');
    revalidatePath('/app/clientes');
    revalidatePath('/app/processos');
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export type SelectedProcessesRefreshActionResult =
  | {
      success: true;
      selectedCount: number;
      completedCount: number;
      failedCount: number;
    }
  | {
      success: false;
      state: 'not_configured' | 'permission_denied' | 'technical_failure';
      message: string;
    };

async function runWithConcurrency<T>(
  values: readonly string[],
  concurrency: number,
  task: (value: string) => Promise<T>
) {
  const results = new Array<T>(values.length);
  let nextIndex = 0;

  async function consume() {
    while (nextIndex < values.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      results[currentIndex] = await task(values[currentIndex]);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(concurrency, values.length) }, () =>
      consume()
    )
  );
  return results;
}

export async function requestSelectedProcessesRefreshAction(
  formData: FormData
): Promise<SelectedProcessesRefreshActionResult> {
  try {
    await requirePermission('manage_monitoring', {
      redirectOnDenied: false,
    });
    const processIds = Array.from(
      new Set(
        formData
          .getAll('processId')
          .filter((value): value is string => typeof value === 'string')
      )
    );
    const parsed = selectedProcessesRefreshSchema.safeParse(processIds);
    if (!parsed.success) {
      return {
        success: false,
        state: 'technical_failure',
        message: 'Selecione pelo menos um processo válido para atualizar.',
      };
    }
    const configuration = getDataJudConfiguration();
    if (configuration.mode !== 'live') {
      return {
        success: false,
        state: 'not_configured',
        message:
          'A consulta da fonte ainda não está configurada neste ambiente.',
      };
    }

    const results = await runWithConcurrency(parsed.data, 2, async (id) => {
      const request = new FormData();
      request.set('processId', id);
      return requestProcessRefreshAction(request);
    });
    const failedCount = results.filter(
      (result) => !('success' in result && result.success)
    ).length;
    const completedCount = results.length - failedCount;
    if (completedCount === 0) {
      return {
        success: false,
        state: 'technical_failure',
        message: 'Não foi possível atualizar os processos selecionados.',
      };
    }
    revalidatePath('/app');
    revalidatePath('/app/clientes');
    revalidatePath('/app/processos');
    return {
      success: true,
      selectedCount: results.length,
      completedCount,
      failedCount,
    };
  } catch (error) {
    return {
      success: false,
      state: 'technical_failure',
      message: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function deactivateProcessAction(formData: FormData) {
  try {
    await requirePermission('create_process', { redirectOnDenied: false });
    const parsed = refreshSchema.safeParse({
      processId: formData.get('processId'),
    });
    if (!parsed.success) {
      return { error: 'Informe um processo válido para exclusão.' };
    }

    const supabase = await createClient();
    const { error } = await supabase.rpc('deactivate_legal_process', {
      p_id: parsed.data.processId,
    });
    if (error) return { error: safeError(error.message) };

    revalidatePath('/app');
    revalidatePath('/app/clientes');
    revalidatePath('/app/processos');
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function requestClientPortfolioRefreshAction(
  formData: FormData
): Promise<PortfolioRefreshActionResult> {
  try {
    await requirePermission('manage_monitoring', {
      redirectOnDenied: false,
    });
    const parsed = portfolioRefreshSchema.safeParse({
      clientId: formData.get('clientId'),
    });
    if (!parsed.success) {
      return {
        success: false,
        state: 'technical_failure',
        message: 'Selecione um cliente válido para atualizar a carteira.',
      };
    }
    const configuration = getDataJudConfiguration();
    if (configuration.mode !== 'live') {
      return {
        success: false,
        state: 'not_configured',
        message:
          'A consulta da fonte ainda não está configurada neste ambiente.',
      };
    }
    const supabase = await createClient();
    const { data, error } = await supabase.rpc(
      'realignment1_request_client_portfolio_refresh',
      { p_client_id: parsed.data.clientId }
    );
    if (error) {
      if (error.message.includes('permission denied')) {
        return {
          success: false,
          state: 'permission_denied',
          message: 'Você não tem autorização para atualizar esta carteira.',
        };
      }
      return {
        success: false,
        state: 'technical_failure',
        message: safeError(error.message),
      };
    }
    const result = Array.isArray(data) ? data[0] : data;
    if (
      !result ||
      (result.state !== 'queued' &&
        result.state !== 'already_running' &&
        result.state !== 'completed') ||
      typeof result.eligible_count !== 'number' ||
      typeof result.skipped_count !== 'number'
    ) {
      return {
        success: false,
        state: 'technical_failure',
        message: 'Não foi possível iniciar a atualização da carteira.',
      };
    }
    revalidatePath('/app');
    revalidatePath('/app/clientes');
    revalidatePath('/app/processos');
    return {
      success: true,
      state: result.state === 'completed' ? 'already_running' : result.state,
      eligibleCount: result.eligible_count,
      skippedCount: result.skipped_count,
    };
  } catch (error) {
    return {
      success: false,
      state: 'technical_failure',
      message: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function getClientPortfolioRefreshProgressAction(
  clientId: string
): Promise<PortfolioProgressActionResult> {
  try {
    await requirePermission('view_operational_data', {
      redirectOnDenied: false,
    });
    const parsed = portfolioRefreshSchema.shape.clientId.safeParse(clientId);
    if (!parsed.success) {
      return { success: false, message: 'Cliente inválido.' };
    }
    const supabase = await createClient();
    const progress = await getClientPortfolioRefreshProgress(
      supabase,
      parsed.data
    );
    return { success: true, progress };
  } catch (error) {
    return {
      success: false,
      message: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function runClientPortfolioRefreshBatchAction(
  clientId: string
): Promise<PortfolioBatchRunActionResult> {
  try {
    await requirePermission('manage_monitoring', {
      redirectOnDenied: false,
    });
    const parsed = portfolioRefreshSchema.shape.clientId.safeParse(clientId);
    if (!parsed.success) {
      return { success: false, message: 'Cliente inválido.' };
    }

    const supabase = await createClient();
    const { data: batch, error: batchError } = await supabase
      .from('process_refresh_batch')
      .select('id,status')
      .eq('client_id', parsed.data)
      .in('status', ['queued', 'running'])
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (batchError || !batch) {
      return {
        success: false,
        message: 'Não há uma atualização de carteira pendente.',
      };
    }

    const { runMonitoringWorkerOnce } = await import('@/lib/monitoring/worker');
    const workerIdPrefix = `portfolio-${Date.now()}`;
    const maxRounds = 200;
    for (let round = 0; round < maxRounds; round += 1) {
      const results = await Promise.allSettled([
        runMonitoringWorkerOnce({
          batchId: batch.id,
          workerId: `${workerIdPrefix}-1`,
        }),
        runMonitoringWorkerOnce({
          batchId: batch.id,
          workerId: `${workerIdPrefix}-2`,
        }),
      ]);
      const failed = results.some((result) => result.status === 'rejected');
      if (failed) break;
      const idle = results.every(
        (result) =>
          result.status === 'fulfilled' && result.value.status === 'idle'
      );
      if (idle) break;
    }

    const progress = await getClientPortfolioRefreshProgress(
      supabase,
      parsed.data
    );
    revalidatePath('/app');
    revalidatePath('/app/clientes');
    revalidatePath('/app/processos');
    return { success: true, progress };
  } catch (error) {
    console.error('Falha ao executar lote da carteira:', error);
    return {
      success: false,
      message: 'Não foi possível concluir a atualização da carteira.',
    };
  }
}

export async function getClientPortfolioProcessDetailAction(
  processId: string
): Promise<PortfolioProcessDetailActionResult> {
  try {
    await requirePermission('view_operational_data', {
      redirectOnDenied: false,
    });
    const parsed = refreshSchema.safeParse({ processId });
    if (!parsed.success)
      return { success: false, message: 'Processo inválido.' };
    const supabase = await createClient();
    const detail = await getClientPortfolioProcessDetail(
      supabase,
      parsed.data.processId
    );
    return { success: true, detail };
  } catch (error) {
    return {
      success: false,
      message: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function createProcessPartyAction(formData: FormData) {
  try {
    await requirePermission('create_process', { redirectOnDenied: false });
    const parsed = relationSchema.safeParse({
      processId: formData.get('processId'),
      partyId: formData.get('partyId'),
      role: formData.get('role'),
      notes: formData.get('notes') || undefined,
    });
    if (!parsed.success)
      return { error: 'Informe parte, papel e observação válidos.' };
    const supabase = await createClient();
    const { data, error } = await supabase.rpc('create_process_party', {
      p_process_id: parsed.data.processId,
      p_party_id: parsed.data.partyId,
      p_role_in_process: parsed.data.role,
      p_source: 'manual',
      p_notes: parsed.data.notes ?? null,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/processos');
    return { success: true, relationId: data };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function confirmProcessPartyAction(formData: FormData) {
  try {
    await requirePermission('confirm_party_links', { redirectOnDenied: false });
    const relationId = z.string().uuid().parse(formData.get('relationId'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('confirm_process_party', {
      p_relation_id: relationId,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/processos');
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function rejectProcessPartyAction(formData: FormData) {
  try {
    await requirePermission('confirm_party_links', { redirectOnDenied: false });
    const relationId = z.string().uuid().parse(formData.get('relationId'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('reject_process_party', {
      p_relation_id: relationId,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/processos');
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function deactivateProcessPartyAction(formData: FormData) {
  try {
    await requirePermission('create_process', { redirectOnDenied: false });
    const relationId = z.string().uuid().parse(formData.get('relationId'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('deactivate_process_party', {
      p_relation_id: relationId,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/processos');
    return { success: true };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

async function resolveImportRows(parsed: ParsedCsv) {
  const supabase = await createClient();
  const [
    { data: clients, error: clientsError },
    { data: parties, error: partiesError },
  ] = await Promise.all([
    supabase.from('client').select('id,party_id,status').eq('status', 'active'),
    supabase
      .from('party')
      .select('id,display_name,normalized_name,status')
      .eq('status', 'active'),
  ]);
  if (clientsError || partiesError)
    throw new Error('Não foi possível carregar as entidades do escritório.');

  const partyById = new Map((parties ?? []).map((party) => [party.id, party]));
  const clientCandidates = (clients ?? []).map((client) => ({
    ...client,
    principal: partyById.get(client.party_id),
  }));
  const errors = [...parsed.errors];
  const resolvedRows: Array<Record<string, unknown>> = [];

  for (const row of parsed.rows) {
    const clientMatches = clientCandidates.filter(
      (client) =>
        client.principal &&
        normalizeName(client.principal.display_name) ===
          normalizeName(row.clientName)
    );
    if (clientMatches.length !== 1) {
      errors.push({
        line: row.line,
        message:
          clientMatches.length > 1
            ? `Linha ${row.line}: cliente homônimo; selecione pelo ID.`
            : `Linha ${row.line}: cliente não encontrado.`,
      });
      continue;
    }
    let partyId: string | null = null;
    if (row.partyName) {
      const partyMatches = (parties ?? []).filter(
        (party) =>
          normalizeName(party.display_name) ===
          normalizeName(row.partyName ?? '')
      );
      if (partyMatches.length !== 1) {
        errors.push({
          line: row.line,
          message:
            partyMatches.length > 1
              ? `Linha ${row.line}: parte homônima; selecione pelo ID.`
              : `Linha ${row.line}: parte não encontrada.`,
        });
        continue;
      }
      partyId = partyMatches[0].id;
    }
    resolvedRows.push({
      cnj_number: row.cnj,
      client_id: clientMatches[0].id,
      tribunal: row.tribunal,
      system: row.system,
      party_id: partyId,
      role_in_process: row.role,
      is_public: row.isPublic,
      monitoring_status: 'paused',
      notes: row.notes,
      source: 'csv',
    });
  }
  return { errors, resolvedRows };
}

export async function previewImportAction(formData: FormData) {
  try {
    await requirePermission('import_csv', { redirectOnDenied: false });
    const fileValue = formData.get('file');
    if (!(fileValue instanceof File) || fileValue.size === 0)
      return { error: 'Selecione um arquivo CSV.' };
    let parsed: ParsedCsv;
    try {
      parsed = await parseCsvFile(fileValue);
    } catch (error) {
      return {
        error: error instanceof Error ? error.message : 'CSV inválido.',
      };
    }
    if (parsed.empty) return { error: 'O CSV está vazio.' };
    const resolved = await resolveImportRows(parsed);
    if (resolved.errors.length > 0) {
      return {
        error: 'A prévia encontrou erros; nenhuma linha foi gravada.',
        errors: resolved.errors,
        warnings: parsed.warnings,
        rows: parsed.rows,
      };
    }
    const summary = {
      total_rows: resolved.resolvedRows.length,
      valid_rows: resolved.resolvedRows.length,
      invalid_rows: 0,
      warning_count: parsed.warnings.length,
    };
    const supabase = await createClient();
    const { data, error } = await supabase.rpc('preview_process_import', {
      p_normalized_rows: resolved.resolvedRows as unknown as Json,
      p_content_hash: parsed.contentHash,
      p_parser_version: CSV_PARSER_VERSION,
      p_summary: summary as unknown as Json,
    });
    if (error)
      return {
        error: safeError(error.message),
        errors: [{ line: 1, message: safeError(error.message) }],
      };
    revalidatePath('/app/processos');
    return {
      success: true,
      preview: data?.[0] ?? null,
      rows: resolved.resolvedRows,
      warnings: parsed.warnings,
    };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}

export async function confirmImportAction(formData: FormData) {
  try {
    await requirePermission('import_csv', { redirectOnDenied: false });
    const previewId = z.string().uuid().parse(formData.get('previewId'));
    const supabase = await createClient();
    const { data, error } = await supabase.rpc('confirm_process_import', {
      p_preview_id: previewId,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/processos');
    return { success: true, summary: data };
  } catch (error) {
    return {
      error: safeError(error instanceof Error ? error.message : undefined),
    };
  }
}
