import { randomUUID } from 'node:crypto';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import {
  addFailureNoteAction,
  assignFailureAction,
  requestFailureReprocessAction,
  resolveFailureAction,
} from '../actions';
import {
  attemptLabel,
  failureClassLabel,
  failureCodeLabel,
  type FailureAssignee,
  type FailureIncidentRow,
  type FailureOccurrenceRow,
} from '@/lib/failures/contract';

function shortId(id: string | null) {
  return id ? id.slice(0, 8) : '—';
}

function formatDate(value: string | null) {
  return value ? new Date(value).toLocaleString('pt-BR') : '—';
}

function eventLabel(kind: FailureOccurrenceRow['event_kind']) {
  return {
    failure_observed: 'Falha observada',
    auto_resolved: 'Resolvido automaticamente',
    manual_resolved: 'Resolvido manualmente',
    reopened: 'Incidente reaberto',
    manual_reprocess_requested: 'Reprocessamento solicitado',
    assignee_changed: 'Responsável alterado',
    operator_note_added: 'Observação adicionada',
  }[kind];
}

export default async function FailureDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { profile } = await requirePermission('view_failures');
  const { id } = await params;
  const supabase = await createClient();
  const { data: incident, error: incidentError } = await supabase
    .from('failure_incident')
    .select('*')
    .eq('id', id)
    .maybeSingle();
  if (incidentError || !incident) notFound();

  const [{ data: occurrenceRows, error: occurrenceError }, { data: job }] =
    await Promise.all([
      supabase
        .from('failure_occurrence')
        .select(
          'id,incident_id,event_kind,origin,failure_stage,failure_class,failure_code,source_type,source_id,query_execution_id,query_job_id,attempt_number,observed_job_status,sanitized_message_code,operator_note_sanitized,resolution_note_sanitized,event_actor_user_id,previous_assignee_user_id,new_assignee_user_id,occurred_at'
        )
        .eq('incident_id', id)
        .order('occurred_at', { ascending: false }),
      incident.current_job_id
        ? supabase
            .from('query_job')
            .select('id,status')
            .eq('id', incident.current_job_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);
  if (occurrenceError)
    throw new Error('Não foi possível carregar o histórico da falha.');
  const typedIncident = incident as unknown as FailureIncidentRow & {
    fingerprint: string;
    recovery_key: string;
    current_execution_id: string | null;
    current_job_id: string | null;
    resolution_kind: string | null;
    resolution_code: string | null;
    resolution_note_sanitized: string | null;
    resolved_at: string | null;
    resolved_by: string | null;
  };
  const occurrences = (occurrenceRows ??
    []) as unknown as FailureOccurrenceRow[];
  const canHandle = profile.role === 'lawyer' || profile.role === 'operator';
  const canReprocess = canHandle && job?.status === 'terminal_failure';
  const actionNonce = randomUUID();
  let assignees: FailureAssignee[] = [];
  if (canHandle) {
    const { data } = await supabase.rpc('phase11_list_failure_assignees');
    assignees = (data ?? []) as unknown as FailureAssignee[];
  }

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between gap-4 px-4">
          <div>
            <Link href="/app" className="font-semibold text-slate-950">
              Juridico
            </Link>
            <p className="text-xs text-slate-500">Detalhe de falha</p>
          </div>
          <Link
            href="/app/falhas"
            className="text-sm font-semibold text-sky-700 hover:underline"
          >
            Voltar à central
          </Link>
        </div>
      </nav>

      <div className="mx-auto max-w-5xl space-y-8 px-4 py-10 sm:px-6 lg:px-8">
        <header>
          <p className="text-sm font-semibold uppercase tracking-wide text-rose-700">
            Incidente {shortId(typedIncident.incident_id)}
          </p>
          <h1 className="mt-2 text-3xl font-bold text-slate-950">
            {failureClassLabel(typedIncident.failure_class)}
          </h1>
          <p className="mt-2 text-slate-600">
            Código{' '}
            <strong>{failureCodeLabel(typedIncident.failure_code)}</strong> ·
            origem {typedIncident.origin} · status{' '}
            {typedIncident.status === 'open' ? 'aberto' : 'resolvido'}.
          </p>
        </header>

        <section className="grid gap-4 rounded-xl border border-slate-200 bg-white p-6 shadow-sm sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Processo
            </p>
            <p className="mt-1 font-semibold text-slate-950">
              {shortId(typedIncident.process_id)}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Primeiro registro
            </p>
            <p className="mt-1 font-semibold text-slate-950">
              {formatDate(typedIncident.first_seen_at)}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Última ocorrência
            </p>
            <p className="mt-1 font-semibold text-slate-950">
              {formatDate(typedIncident.last_seen_at)}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Falhas observadas
            </p>
            <p className="mt-1 font-semibold text-slate-950">
              {typedIncident.occurrence_count}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Tentativa atual/última
            </p>
            <p className="mt-1 font-semibold text-slate-950">
              {attemptLabel(
                occurrences.find((item) => item.attempt_number !== null)
                  ?.attempt_number ?? null
              )}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Execução atual
            </p>
            <p className="mt-1 font-mono text-sm text-slate-950">
              {shortId(typedIncident.current_execution_id)}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Responsável
            </p>
            <p className="mt-1 font-mono text-sm text-slate-950">
              {shortId(typedIncident.assigned_to_user_id)}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-slate-500">
              Próximo job
            </p>
            <p className="mt-1 text-sm font-semibold text-slate-950">
              {job?.status ?? 'Não se aplica'}
            </p>
          </div>
        </section>

        {canHandle ? (
          <section className="grid gap-6 lg:grid-cols-2">
            <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
              <h2 className="text-lg font-semibold text-slate-950">
                Tratamento operacional
              </h2>
              <p className="mt-1 text-sm text-slate-600">
                Toda ação é revalidada no banco e registrada na linha do tempo e
                na auditoria.
              </p>
              {canReprocess ? (
                <form
                  action={async (formData) => {
                    'use server';
                    await requestFailureReprocessAction(formData);
                  }}
                  className="mt-4 space-y-3"
                >
                  <input type="hidden" name="incidentId" value={id} />
                  <input
                    type="hidden"
                    name="idempotencyKey"
                    value={`ui-${id}-reprocess-${actionNonce}`}
                  />
                  <button
                    type="submit"
                    className="rounded-md bg-amber-700 px-4 py-2 font-semibold text-white hover:bg-amber-800"
                  >
                    Solicitar reprocessamento
                  </button>
                </form>
              ) : (
                <p className="mt-4 text-sm text-slate-600">
                  Reprocessamento indisponível: o job atual não está em falha
                  terminal ou não há job associado.
                </p>
              )}
              {typedIncident.status === 'open' ? (
                <form
                  action={async (formData) => {
                    'use server';
                    await resolveFailureAction(formData);
                  }}
                  className="mt-6 space-y-3 border-t border-slate-200 pt-5"
                >
                  <input type="hidden" name="incidentId" value={id} />
                  <input
                    type="hidden"
                    name="idempotencyKey"
                    value={`ui-${id}-resolve-${actionNonce}`}
                  />
                  <label className="block text-sm font-medium text-slate-700">
                    Motivo da resolução
                    <select
                      name="resolutionCode"
                      defaultValue="closed_by_operator"
                      className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
                    >
                      <option value="closed_by_operator">
                        Encerrado pelo operador
                      </option>
                      <option value="not_reproducible">Não reproduzível</option>
                      <option value="manual_review_complete">
                        Revisão manual concluída
                      </option>
                      <option value="reprocessed">Reprocessado</option>
                    </select>
                  </label>
                  <label className="block text-sm font-medium text-slate-700">
                    Observação obrigatória
                    <textarea
                      name="resolutionNote"
                      required
                      maxLength={2000}
                      className="mt-1 min-h-24 w-full rounded-md border border-slate-300 px-3 py-2"
                    />
                  </label>
                  <button
                    type="submit"
                    className="rounded-md bg-emerald-700 px-4 py-2 font-semibold text-white hover:bg-emerald-800"
                  >
                    Registrar resolução
                  </button>
                </form>
              ) : null}
            </div>

            <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
              <h2 className="text-lg font-semibold text-slate-950">
                Responsável e observação
              </h2>
              <form
                action={async (formData) => {
                  'use server';
                  await assignFailureAction(formData);
                }}
                className="mt-4 space-y-3"
              >
                <input type="hidden" name="incidentId" value={id} />
                <input
                  type="hidden"
                  name="idempotencyKey"
                  value={`ui-${id}-assignee-${actionNonce}`}
                />
                <label className="block text-sm font-medium text-slate-700">
                  Responsável
                  <select
                    name="assigneeUserId"
                    defaultValue={typedIncident.assigned_to_user_id ?? ''}
                    className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
                  >
                    <option value="">Sem responsável</option>
                    {assignees.map((assignee) => (
                      <option key={assignee.id} value={assignee.id}>
                        {assignee.name} · {assignee.role}
                      </option>
                    ))}
                  </select>
                </label>
                <button
                  type="submit"
                  className="rounded-md border border-slate-300 px-4 py-2 font-semibold text-slate-700 hover:bg-slate-50"
                >
                  Salvar responsável
                </button>
              </form>
              <form
                action={async (formData) => {
                  'use server';
                  await addFailureNoteAction(formData);
                }}
                className="mt-6 space-y-3 border-t border-slate-200 pt-5"
              >
                <input type="hidden" name="incidentId" value={id} />
                <input
                  type="hidden"
                  name="idempotencyKey"
                  value={`ui-${id}-note-${actionNonce}`}
                />
                <label className="block text-sm font-medium text-slate-700">
                  Nova observação
                  <textarea
                    name="note"
                    required
                    maxLength={2000}
                    className="mt-1 min-h-24 w-full rounded-md border border-slate-300 px-3 py-2"
                  />
                </label>
                <button
                  type="submit"
                  className="rounded-md bg-sky-700 px-4 py-2 font-semibold text-white hover:bg-sky-800"
                >
                  Adicionar observação
                </button>
              </form>
            </div>
          </section>
        ) : null}

        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-slate-950">
            Linha do tempo append-only
          </h2>
          <p className="mt-1 text-sm text-slate-600">
            Cada registro representa um evento histórico. O contador acima conta
            apenas eventos “falha observada”, nunca o número da tentativa.
          </p>
          <div className="mt-5 space-y-4">
            {occurrences.length === 0 ? (
              <p className="text-sm text-slate-500">
                Nenhum evento histórico encontrado.
              </p>
            ) : null}
            {occurrences.map((occurrence) => (
              <article
                key={occurrence.id}
                className="border-l-2 border-slate-300 pl-4"
              >
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <h3 className="font-semibold text-slate-950">
                    {eventLabel(occurrence.event_kind)}
                  </h3>
                  <time className="text-xs text-slate-500">
                    {formatDate(occurrence.occurred_at)}
                  </time>
                </div>
                <p className="mt-1 text-sm text-slate-700">
                  {occurrence.failure_code
                    ? failureCodeLabel(occurrence.failure_code)
                    : 'Evento operacional'}{' '}
                  · tentativa {attemptLabel(occurrence.attempt_number)} · origem{' '}
                  {occurrence.origin}
                </p>
                <p className="mt-1 text-xs text-slate-500">
                  Fonte {occurrence.source_type} · referência{' '}
                  {shortId(occurrence.source_id)} · evento{' '}
                  {shortId(occurrence.id)}
                </p>
                {occurrence.operator_note_sanitized ? (
                  <p className="mt-2 rounded-md bg-slate-50 p-3 text-sm text-slate-700">
                    Observação: {occurrence.operator_note_sanitized}
                  </p>
                ) : null}
                {occurrence.resolution_note_sanitized ? (
                  <p className="mt-2 rounded-md bg-emerald-50 p-3 text-sm text-emerald-900">
                    Resolução: {occurrence.resolution_note_sanitized}
                  </p>
                ) : null}
              </article>
            ))}
          </div>
        </section>

        {typedIncident.status === 'resolved' ? (
          <section className="rounded-xl border border-emerald-200 bg-emerald-50 p-5 text-sm text-emerald-950">
            Resolvido em {formatDate(typedIncident.resolved_at)} por{' '}
            {shortId(typedIncident.resolved_by)}. Uma nova falha com a mesma
            chave de recuperação poderá reabrir o incidente e preservará o
            histórico anterior.
          </section>
        ) : null}
      </div>
    </main>
  );
}
