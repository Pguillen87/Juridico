import Link from 'next/link';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import {
  attemptLabel,
  failureClassLabel,
  failureCodeLabel,
  type FailureAssignee,
  type FailureIncidentRow,
} from '@/lib/failures/contract';

function shortId(id: string | null) {
  return id ? id.slice(0, 8) : '—';
}

function formatDate(value: string | null) {
  return value ? new Date(value).toLocaleString('pt-BR') : '—';
}

function textParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function FailuresPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { profile } = await requirePermission('view_failures');
  const params = searchParams ? await searchParams : {};
  const type = textParam(params.type) ?? '';
  const processId = textParam(params.processId) ?? '';
  const fromDate = textParam(params.from) ?? '';
  const toDate = textParam(params.to) ?? '';
  const priority = textParam(params.priority) ?? '';
  const attempt = textParam(params.attempt) ?? '';
  const status = textParam(params.status) ?? 'open';
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('phase11_list_failure_incidents', {
    p_failure_type: type || null,
    p_process_id: processId || null,
    p_from_date: fromDate || null,
    p_to_date: toDate || null,
    p_priority: priority || null,
    p_attempt_number: attempt ? Number(attempt) : null,
    p_status: status || null,
    p_limit: 100,
  });
  if (error) throw new Error('Não foi possível carregar a central de falhas.');
  const incidents = (data ?? []) as unknown as FailureIncidentRow[];
  let assignees: FailureAssignee[] = [];
  const canHandle = profile.role === 'lawyer' || profile.role === 'operator';
  if (canHandle) {
    const assigneeResponse = await supabase.rpc(
      'phase11_list_failure_assignees'
    );
    if (!assigneeResponse.error)
      assignees = (assigneeResponse.data ?? []) as unknown as FailureAssignee[];
  }

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between gap-4 px-4">
          <div>
            <Link href="/app" className="font-semibold text-slate-950">
              Juridico
            </Link>
            <p className="text-xs text-slate-500">Central operacional</p>
          </div>
          <div className="flex gap-4 text-sm">
            <Link
              className="text-sky-700 hover:underline"
              href="/app/processos"
            >
              Processos
            </Link>
            <Link className="text-slate-600 hover:underline" href="/app">
              Área protegida
            </Link>
          </div>
        </div>
      </nav>

      <div className="mx-auto max-w-7xl space-y-8 px-4 py-10 sm:px-6 lg:px-8">
        <header>
          <p className="text-sm font-semibold uppercase tracking-wide text-rose-700">
            US-028 · US-029 · US-030 · US-031
          </p>
          <h1 className="mt-2 text-3xl font-bold text-slate-950">
            Central de falhas
          </h1>
          <p className="mt-2 max-w-3xl text-slate-600">
            Consulte falhas operacionais persistidas, acompanhe cada ocorrência
            e trate somente o que está autorizado. Uma falha nunca é
            interpretada como ausência de alteração: <strong>unchanged</strong>{' '}
            permanece um resultado comparativo separado.
          </p>
        </header>

        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-slate-950">
            Filtros server-side
          </h2>
          <p className="mt-1 text-sm text-slate-600">
            O filtro por tentativa considera somente ocorrências ligadas a uma
            execução. Falhas de scheduler ou infraestrutura sem tentativa
            aparecem como “não se aplica”.
          </p>
          <form
            method="get"
            className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4"
          >
            <label className="text-sm font-medium text-slate-700">
              Tipo de falha
              <select
                name="type"
                defaultValue={type}
                className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
              >
                <option value="">Todos os tipos</option>
                <option value="provider_transient">Fonte temporária</option>
                <option value="provider_permanent">
                  Fonte não recuperável
                </option>
                <option value="provider_manual_review">Revisão manual</option>
                <option value="persistence">Persistência</option>
                <option value="comparison">Comparação</option>
                <option value="scheduler">Agendamento</option>
                <option value="worker">Worker</option>
                <option value="notification">Notificação</option>
              </select>
            </label>
            <label className="text-sm font-medium text-slate-700">
              Processo por ID
              <input
                name="processId"
                defaultValue={processId}
                placeholder="UUID do processo"
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="text-sm font-medium text-slate-700">
              Data inicial
              <input
                type="date"
                name="from"
                defaultValue={fromDate}
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="text-sm font-medium text-slate-700">
              Data final
              <input
                type="date"
                name="to"
                defaultValue={toDate}
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="text-sm font-medium text-slate-700">
              Tentativa
              <select
                name="attempt"
                defaultValue={attempt}
                className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
              >
                <option value="">Todas as tentativas</option>
                <option value="1">Tentativa 1</option>
                <option value="2">Tentativa 2</option>
                <option value="3">Tentativa 3</option>
              </select>
            </label>
            <label className="text-sm font-medium text-slate-700">
              Prioridade
              <select
                name="priority"
                defaultValue={priority}
                className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
              >
                <option value="">Todas as prioridades</option>
                <option value="high">Alta</option>
                <option value="medium">Média</option>
                <option value="low">Baixa</option>
              </select>
            </label>
            <label className="text-sm font-medium text-slate-700">
              Situação
              <select
                name="status"
                defaultValue={status}
                className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
              >
                <option value="open">Abertas</option>
                <option value="resolved">Resolvidas</option>
                <option value="">Todas</option>
              </select>
            </label>
            <div className="flex items-end gap-3">
              <button
                type="submit"
                className="rounded-md bg-slate-900 px-4 py-2 font-semibold text-white hover:bg-slate-800"
              >
                Aplicar filtros
              </button>
              <Link
                href="/app/falhas"
                className="rounded-md border border-slate-300 px-4 py-2 font-semibold text-slate-700 hover:bg-slate-50"
              >
                Limpar
              </Link>
            </div>
          </form>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-200 p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="text-lg font-semibold text-slate-950">
                  Incidentes rastreáveis
                </h2>
                <p className="mt-1 text-sm text-slate-600">
                  {incidents.length} incidente(s) nesta consulta. O contador
                  indica somente quantidade de falhas observadas.
                </p>
              </div>
              <span
                className="rounded-full bg-rose-100 px-3 py-1 text-sm font-semibold text-rose-800"
                aria-label="Quantidade de incidentes"
              >
                {incidents.length}
              </span>
            </div>
          </div>
          <div className="divide-y divide-slate-200">
            {incidents.length === 0 ? (
              <p className="p-6 text-sm text-slate-600">
                Nenhuma falha corresponde aos filtros informados.
              </p>
            ) : null}
            {incidents.map((incident) => (
              <article key={incident.incident_id} className="p-6">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="font-semibold text-slate-950">
                        {failureClassLabel(incident.failure_class)}
                      </h3>
                      <span
                        className={
                          incident.operational_priority === 'high'
                            ? 'rounded-full bg-rose-100 px-2 py-1 text-xs font-semibold text-rose-800'
                            : incident.operational_priority === 'medium'
                              ? 'rounded-full bg-amber-100 px-2 py-1 text-xs font-semibold text-amber-900'
                              : 'rounded-full bg-emerald-100 px-2 py-1 text-xs font-semibold text-emerald-800'
                        }
                      >
                        Prioridade{' '}
                        {incident.operational_priority === 'high'
                          ? 'alta'
                          : incident.operational_priority === 'medium'
                            ? 'média'
                            : 'baixa'}
                      </span>
                      <span className="rounded-full bg-slate-100 px-2 py-1 text-xs font-semibold text-slate-700">
                        {incident.status === 'open' ? 'Aberto' : 'Resolvido'}
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-slate-700">
                      {failureCodeLabel(incident.failure_code)} · origem{' '}
                      {incident.origin}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      Incidente {shortId(incident.incident_id)} · processo{' '}
                      {shortId(incident.process_id)} · última ocorrência{' '}
                      {formatDate(incident.last_seen_at)}
                    </p>
                  </div>
                  <Link
                    href={`/app/falhas/${incident.incident_id}`}
                    className="rounded-md bg-sky-700 px-3 py-2 text-sm font-semibold text-white hover:bg-sky-800"
                  >
                    Ver detalhe
                  </Link>
                </div>
                <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-4">
                  <div className="rounded-md bg-slate-50 p-3">
                    <dt className="text-slate-500">Falhas observadas</dt>
                    <dd className="font-semibold text-slate-950">
                      {incident.occurrence_count}
                    </dd>
                  </div>
                  <div className="rounded-md bg-slate-50 p-3">
                    <dt className="text-slate-500">Tentativa atual/última</dt>
                    <dd className="font-semibold text-slate-950">
                      {attemptLabel(incident.last_attempt_number)}
                    </dd>
                  </div>
                  <div className="rounded-md bg-slate-50 p-3">
                    <dt className="text-slate-500">Próxima ação</dt>
                    <dd className="font-semibold text-slate-950">
                      {incident.next_action_code}
                    </dd>
                  </div>
                  <div className="rounded-md bg-slate-50 p-3">
                    <dt className="text-slate-500">Responsável</dt>
                    <dd className="font-semibold text-slate-950">
                      {shortId(incident.assigned_to_user_id)}
                    </dd>
                  </div>
                </dl>
                {canHandle ? (
                  <p className="mt-3 text-xs text-slate-500">
                    Tratamento operacional disponível no detalhe; o banco
                    revalida escritório, perfil ativo e papel permitido.
                  </p>
                ) : null}
              </article>
            ))}
          </div>
        </section>

        {canHandle && assignees.length === 0 ? (
          <p className="text-sm text-slate-500">
            Nenhum lawyer/operator ativo está disponível para atribuição neste
            escritório.
          </p>
        ) : null}
      </div>
    </main>
  );
}
