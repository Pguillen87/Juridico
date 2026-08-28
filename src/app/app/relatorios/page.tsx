import Link from 'next/link';
import { displayReportStatus, type ReportStatus } from '@/lib/reports/contract';
import { listReports, requireReportAccess } from '@/lib/reports/server';

function textParam(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? '') : (value ?? '');
}

function shortId(value: string | null): string {
  return value ? value.slice(0, 8) : '—';
}

function formatDate(value: string | null): string {
  return value ? new Date(value).toLocaleString('pt-BR') : '—';
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireReportAccess();
  const params = searchParams ? await searchParams : {};
  const status = textParam(params.status);
  const clientId = textParam(params.clientId);
  const from = textParam(params.from);
  const to = textParam(params.to);
  const reports = await listReports({
    ...(status ? { status: status as ReportStatus } : {}),
    ...(clientId ? { clientId } : {}),
    ...(from ? { periodStart: from } : {}),
    ...(to ? { periodEnd: to } : {}),
  });

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between gap-4 px-4">
          <div>
            <Link href="/app" className="font-semibold text-slate-950">
              Juridico
            </Link>
            <p className="text-xs text-slate-500">Área protegida</p>
          </div>
          <div className="flex gap-4 text-sm">
            <Link
              className="text-sky-700 hover:underline"
              href="/app/processos"
            >
              Processos
            </Link>
            <Link className="text-sky-700 hover:underline" href="/app/falhas">
              Falhas
            </Link>
          </div>
        </div>
      </nav>

      <div className="mx-auto max-w-7xl space-y-8 px-4 py-10 sm:px-6 lg:px-8">
        <header>
          <p className="text-sm font-semibold uppercase tracking-wide text-sky-700">
            US-032 · US-033 · US-034 · US-035 · US-036 · US-037
          </p>
          <h1 className="mt-2 text-3xl font-bold text-slate-950">
            Relatórios semanais
          </h1>
          <p className="mt-2 max-w-3xl text-slate-600">
            Consulte versões congeladas por cliente e período. Alterações,
            ausência de alteração comprovada, resultados não comparáveis e
            falhas permanecem estados distintos. Aprovação não significa envio.
          </p>
        </header>

        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-slate-950">Filtros</h2>
          <p className="mt-1 text-sm text-slate-600">
            A consulta é server-side e limitada ao escritório da sessão ativa.
          </p>
          <p className="mt-2 text-sm text-slate-600">
            Aprovação não significa envio.
          </p>
          <form
            method="get"
            className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-5"
          >
            <label className="text-sm font-medium text-slate-700">
              Cliente por ID
              <input
                name="clientId"
                defaultValue={clientId}
                placeholder="UUID do cliente"
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="text-sm font-medium text-slate-700">
              Período desde
              <input
                type="date"
                name="from"
                defaultValue={from}
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="text-sm font-medium text-slate-700">
              Período até
              <input
                type="date"
                name="to"
                defaultValue={to}
                className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
              />
            </label>
            <label className="text-sm font-medium text-slate-700">
              Status
              <select
                name="status"
                defaultValue={status}
                className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
              >
                <option value="">Todos os status</option>
                <option value="draft">Rascunho</option>
                <option value="awaiting_review">Aguardando revisão</option>
                <option value="approved">Aprovado</option>
                <option value="cancelled">Cancelado</option>
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
                href="/app/relatorios"
                className="rounded-md border border-slate-300 px-4 py-2 font-semibold text-slate-700 hover:bg-slate-50"
              >
                Limpar
              </Link>
            </div>
          </form>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-950">
              Relatórios encontrados
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              {reports.length} relatório(s) nesta consulta.
            </p>
          </div>
          <div className="divide-y divide-slate-200">
            {reports.length === 0 ? (
              <p className="p-6 text-sm text-slate-600">
                Nenhum relatório corresponde aos filtros informados.
              </p>
            ) : null}
            {reports.map((report) => (
              <article key={report.id} className="p-6">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="font-semibold text-slate-950">
                        Cliente {shortId(report.client_id)} · período semanal
                      </h3>
                      <span className="rounded-full bg-slate-100 px-2 py-1 text-xs font-semibold text-slate-700">
                        {displayReportStatus(report.status)}
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-slate-700">
                      {new Date(report.period_start_utc).toLocaleDateString(
                        'pt-BR'
                      )}{' '}
                      até{' '}
                      {new Date(report.period_end_utc).toLocaleDateString(
                        'pt-BR'
                      )}{' '}
                      · {report.timezone}
                    </p>
                    <p className="mt-1 text-xs text-slate-500">
                      Relatório {shortId(report.id)} · versão atual{' '}
                      {shortId(report.current_version_id)} · atualizado{' '}
                      {formatDate(report.updated_at)}
                    </p>
                  </div>
                  <Link
                    href={`/app/relatorios/${report.id}`}
                    className="rounded-md bg-sky-700 px-3 py-2 text-sm font-semibold text-white hover:bg-sky-800"
                  >
                    Ver detalhe
                  </Link>
                </div>
                <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-3">
                  <div className="rounded-md bg-slate-50 p-3">
                    <dt className="text-slate-500">Versão aprovada</dt>
                    <dd className="font-semibold text-slate-950">
                      {shortId(report.approved_version_id)}
                    </dd>
                  </div>
                  <div className="rounded-md bg-slate-50 p-3">
                    <dt className="text-slate-500">Hash aprovado</dt>
                    <dd className="font-semibold text-slate-950">
                      {report.approved_hash?.slice(0, 12) ?? '—'}
                    </dd>
                  </div>
                  <div className="rounded-md bg-slate-50 p-3">
                    <dt className="text-slate-500">Aprovação</dt>
                    <dd className="font-semibold text-slate-950">
                      {formatDate(report.approved_at)}
                    </dd>
                  </div>
                </dl>
              </article>
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}
