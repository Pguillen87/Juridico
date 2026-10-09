import Link from 'next/link';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { createClientAction } from './actions';
import { RefreshClientPortfolioButton } from './refresh-client-portfolio-button';
import { getClientPortfolioReadModels } from '@/lib/clients/portfolio';

function statusLabel(status: string) {
  return status === 'active' ? 'Ativo' : 'Inativo';
}

function formatDate(value: string | null) {
  return value
    ? new Date(value).toLocaleString('pt-BR')
    : 'Ainda não disponível';
}

export default async function ClientsPage() {
  const { profile } = await requirePermission('view_operational_data');
  const canMutate = profile.role === 'lawyer' || profile.role === 'operator';
  const supabase = await createClient();
  const [
    { data: clients, error: clientsError },
    { data: clientNames, error: namesError },
  ] = await Promise.all([
    supabase
      .from('client')
      .select('id,party_id,status')
      .order('created_at', { ascending: false }),
    supabase.from('party').select('id,display_name').order('display_name'),
  ]);
  const portfolios = await getClientPortfolioReadModels(supabase);

  if (clientsError || namesError) {
    throw new Error('Não foi possível carregar os clientes.');
  }

  const nameById = new Map(
    (clientNames ?? []).map((clientName) => [
      clientName.id,
      clientName.display_name,
    ])
  );
  const portfolioByClient = new Map(
    portfolios.map((portfolio) => [portfolio.clientId, portfolio])
  );

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between px-4">
          <div className="flex items-center gap-6">
            <Link href="/app" className="group">
              <span className="font-semibold text-slate-950 group-hover:text-sky-700">
                Juridico
              </span>
              <p className="text-xs text-slate-500">Início</p>
            </Link>
            <div className="flex items-center gap-4 text-sm font-medium">
              <Link
                className="text-slate-700 hover:text-sky-700"
                href="/app/processos"
              >
                Processos
              </Link>
              <Link className="font-semibold text-sky-700" href="/app/clientes">
                Clientes
              </Link>
              <Link
                className="text-slate-700 hover:text-sky-700"
                href="/app/falhas"
              >
                Central de falhas
              </Link>
              <Link
                className="text-slate-700 hover:text-sky-700"
                href="/app/relatorios"
              >
                Relatórios
              </Link>
            </div>
          </div>
          <Link
            href="/app"
            className="text-sm font-semibold text-sky-700 hover:underline"
          >
            Voltar ao Início
          </Link>
        </div>
      </nav>

      <div className="mx-auto max-w-7xl space-y-8 px-4 py-10 sm:px-6 lg:px-8">
        <header>
          <p className="text-sm font-semibold uppercase tracking-wide text-sky-700">
            Carteira
          </p>
          <h1 className="mt-2 text-3xl font-bold text-slate-950">Clientes</h1>
          <p className="mt-2 max-w-3xl text-slate-600">
            Cada cliente reúne seus processos cadastrados. Abra a carteira para
            pesquisar, atualizar e exportar os processos.
          </p>
        </header>

        {canMutate ? (
          <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div>
                <h2 className="text-lg font-semibold text-slate-950">
                  Novo cliente
                </h2>
                <p className="mt-1 text-sm text-slate-600">
                  Informe somente o nome que será usado para organizar a
                  carteira.
                </p>
              </div>
              <form
                action={async (formData) => {
                  'use server';
                  await createClientAction(formData);
                }}
                className="flex w-full flex-wrap items-end gap-3 lg:w-auto"
              >
                <input type="hidden" name="partyType" value="person" />
                <label className="min-w-64 flex-1 text-sm font-medium text-slate-700 lg:flex-none">
                  Nome do cliente
                  <input
                    name="displayName"
                    required
                    minLength={2}
                    maxLength={200}
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  />
                </label>
                <button
                  className="rounded-md bg-sky-700 px-4 py-2 font-semibold text-white hover:bg-sky-800"
                  type="submit"
                >
                  Criar cliente
                </button>
              </form>
            </div>
          </section>
        ) : null}

        <section className="space-y-4">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 className="text-2xl font-semibold text-slate-950">
                Carteira de clientes
              </h2>
              <p className="mt-1 text-sm text-slate-600">
                Acompanhe a quantidade de processos e abra uma carteira para ver
                a grade completa.
              </p>
            </div>
            <Link
              href="/app/processos"
              className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-700 hover:border-sky-500 hover:text-sky-700"
            >
              Ver todos os processos
            </Link>
          </div>

          {(clients ?? []).length === 0 ? (
            <div className="rounded-xl border border-dashed border-slate-300 bg-white p-8 text-center text-sm text-slate-600">
              Nenhum cliente cadastrado.
            </div>
          ) : (
            <div className="grid gap-5 lg:grid-cols-2">
              {(clients ?? []).map((client) => {
                const portfolio = portfolioByClient.get(client.id);
                const clientName =
                  nameById.get(client.party_id ?? '') ?? 'Cliente sem nome';

                return (
                  <article
                    key={client.id}
                    className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
                  >
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <h3 className="text-lg font-semibold text-slate-950">
                          {clientName}
                        </h3>
                        <p className="mt-1 text-sm text-slate-600">
                          {statusLabel(client.status)} ·{' '}
                          {portfolio?.processCount ?? 0} processo(s)
                        </p>
                      </div>
                      <div className="flex flex-wrap gap-3 text-sm font-semibold">
                        <Link
                          href={`/app/processos?clientId=${client.id}`}
                          className="text-sky-700 hover:underline"
                        >
                          Abrir carteira
                        </Link>
                        {canMutate ? (
                          <Link
                            href={`/app/processos?clientId=${client.id}&add=1`}
                            className="text-emerald-700 hover:underline"
                          >
                            Adicionar processo
                          </Link>
                        ) : null}
                      </div>
                    </div>

                    <div className="mt-4 grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
                      <div className="rounded-md bg-slate-50 p-3">
                        <p className="text-xs text-slate-500">Processos</p>
                        <p className="mt-1 text-lg font-semibold text-slate-950">
                          {portfolio?.processCount ?? 0}
                        </p>
                      </div>
                      <div className="rounded-md bg-amber-50 p-3">
                        <p className="text-xs text-slate-500">Novidades</p>
                        <p className="mt-1 text-lg font-semibold text-amber-800">
                          {portfolio?.noveltyCount ?? 0}
                        </p>
                      </div>
                      <div className="rounded-md bg-slate-50 p-3">
                        <p className="text-xs text-slate-500">
                          Não consultados
                        </p>
                        <p className="mt-1 text-lg font-semibold text-slate-800">
                          {portfolio?.notUpdatedCount ?? 0}
                        </p>
                      </div>
                      <div className="rounded-md bg-rose-50 p-3">
                        <p className="text-xs text-slate-500">Atenção</p>
                        <p className="mt-1 text-lg font-semibold text-rose-800">
                          {(portfolio?.failureCount ?? 0) +
                            (portfolio?.reviewCount ?? 0)}
                        </p>
                      </div>
                    </div>

                    <div className="mt-4 grid gap-2 text-xs text-slate-600 sm:grid-cols-2">
                      <p>
                        Última consulta:{' '}
                        {formatDate(portfolio?.lastConsultedAt ?? null)}
                      </p>
                      <p>
                        Atualização da fonte:{' '}
                        {formatDate(portfolio?.lastSourceUpdatedAt ?? null)}
                      </p>
                    </div>

                    {canMutate ? (
                      <div className="mt-4 border-t border-slate-100 pt-4">
                        <RefreshClientPortfolioButton clientId={client.id} />
                      </div>
                    ) : null}
                  </article>
                );
              })}
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
