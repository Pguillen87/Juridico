import Link from 'next/link';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import {
  confirmRelatedPartyAction,
  createClientAction,
  createPartyAction,
  createRelatedPartyAction,
  deactivatePartyAction,
  deactivateRelatedPartyAction,
  rejectRelatedPartyAction,
  updatePartyAction,
} from './actions';
import { RefreshProcessButton } from '../processos/refresh-process-button';
import {
  getClientPortfolioReadModels,
  type ClientPortfolioProcess,
} from '@/lib/clients/portfolio';

const relationTypes = [
  'subsidiary',
  'family_member',
  'dependent',
  'representative',
  'other',
] as const;

function shortId(id: string) {
  return id.slice(0, 8);
}

function statusLabel(status: string) {
  return status === 'active' ? 'Ativo' : 'Inativo';
}

function confirmationLabel(status: string) {
  if (status === 'confirmed') return 'Confirmada';
  if (status === 'rejected') return 'Rejeitada';
  return 'Pendente';
}

function portfolioStateLabel(process: ClientPortfolioProcess) {
  switch (process.state) {
    case 'not_consulted':
      return 'Este processo ainda não foi atualizado.';
    case 'updating':
      return 'Atualizando processo...';
    case 'first_observation':
      return `Primeira consulta concluída — ${process.newMovementCount} movimentações disponíveis.`;
    case 'changed':
      return `${process.newMovementCount} novas movimentações desde a última consulta.`;
    case 'failure':
      return 'Não foi possível concluir a consulta.';
    case 'manual_review':
      return 'Encontramos uma inconsistência nos dados da fonte. É necessária revisão.';
    case 'unchanged':
      return 'Sem novas movimentações desde a última consulta.';
  }
}

function formatDate(value: string | null) {
  return value
    ? new Date(value).toLocaleString('pt-BR')
    : 'Ainda não disponível';
}

export default async function ClientsPage() {
  const { profile } = await requirePermission('view_operational_data');
  const canMutate = profile.role === 'lawyer' || profile.role === 'operator';
  const canConfirm = profile.role === 'lawyer';
  const supabase = await createClient();
  const [
    { data: clients, error: clientsError },
    { data: parties, error: partiesError },
    { data: relations, error: relationsError },
  ] = await Promise.all([
    supabase
      .from('client')
      .select('id,status,party_id')
      .order('created_at', { ascending: false }),
    supabase
      .from('party')
      .select('id,display_name,party_type,status')
      .order('display_name'),
    supabase
      .from('client_related_party')
      .select(
        'id,client_id,party_id,relation_type,status,confirmation_status,confirmed_by,confirmed_at,notes'
      )
      .order('created_at', { ascending: false }),
  ]);
  const portfolios = await getClientPortfolioReadModels(supabase);
  if (clientsError || partiesError || relationsError) {
    throw new Error('Não foi possível carregar os dados operacionais.');
  }

  const partyById = new Map((parties ?? []).map((party) => [party.id, party]));
  const relationsByClient = new Map<string, typeof relations>();
  for (const relation of relations ?? []) {
    const current = relationsByClient.get(relation.client_id) ?? [];
    current.push(relation);
    relationsByClient.set(relation.client_id, current);
  }
  const clientPrincipalIds = new Set(
    (clients ?? []).map((client) => client.party_id)
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
                Clientes e partes
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
            RF-003
          </p>
          <h1 className="mt-2 text-3xl font-bold text-slate-950">
            Clientes, partes e vínculos
          </h1>
          <p className="mt-2 max-w-3xl text-slate-600">
            Cadastre entidades do seu escritório. Nomes iguais permanecem
            registros distintos; a seleção usa ID e nenhuma relação é confirmada
            automaticamente.
          </p>
        </header>

        <section className={canMutate ? 'grid gap-6 lg:grid-cols-2' : 'hidden'}>
          <form
            action={async (formData) => {
              'use server';
              await createClientAction(formData);
            }}
            className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
          >
            <h2 className="text-lg font-semibold text-slate-950">
              Novo cliente
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              Cliente e parte principal são criados na mesma transação.
            </p>
            <div className="mt-5 space-y-4">
              <label className="block text-sm font-medium text-slate-700">
                Nome
                <input
                  name="displayName"
                  required
                  minLength={2}
                  maxLength={200}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                />
              </label>
              <label className="block text-sm font-medium text-slate-700">
                Tipo
                <select
                  name="partyType"
                  defaultValue="person"
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                >
                  <option value="person">Pessoa física</option>
                  <option value="company">Pessoa jurídica</option>
                  <option value="other">Outro</option>
                </select>
              </label>
              <button
                className="rounded-md bg-sky-700 px-4 py-2 font-semibold text-white hover:bg-sky-800"
                type="submit"
              >
                Criar cliente
              </button>
            </div>
          </form>
          <form
            action={async (formData) => {
              'use server';
              await createPartyAction(formData);
            }}
            className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
          >
            <h2 className="text-lg font-semibold text-slate-950">Nova parte</h2>
            <p className="mt-1 text-sm text-slate-600">
              A parte será restrita ao office do usuário autenticado.
            </p>
            <div className="mt-5 space-y-4">
              <label className="block text-sm font-medium text-slate-700">
                Nome
                <input
                  name="displayName"
                  required
                  minLength={2}
                  maxLength={200}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                />
              </label>
              <label className="block text-sm font-medium text-slate-700">
                Tipo
                <select
                  name="partyType"
                  defaultValue="person"
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                >
                  <option value="person">Pessoa física</option>
                  <option value="company">Pessoa jurídica</option>
                  <option value="other">Outro</option>
                </select>
              </label>
              <button
                className="rounded-md bg-slate-900 px-4 py-2 font-semibold text-white hover:bg-slate-700"
                type="submit"
              >
                Criar parte
              </button>
            </div>
          </form>
        </section>
        <section className="space-y-4">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 className="text-2xl font-semibold text-slate-950">
                Carteira de clientes
              </h2>
              <p className="mt-1 text-sm text-slate-600">
                Processos cadastrados manualmente e consulta individual por CNJ.
              </p>
            </div>
            {canMutate ? (
              <Link
                href="/app/processos"
                className="rounded-md bg-sky-700 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-800"
              >
                Adicionar processo
              </Link>
            ) : null}
          </div>
          <div className="grid gap-5 lg:grid-cols-2">
            {(clients ?? []).map((client) => {
              const principal = partyById.get(client.party_id);
              const portfolio = portfolioByClient.get(client.id);
              const clientRelations = relationsByClient.get(client.id) ?? [];
              const candidates = (parties ?? []).filter(
                (party) =>
                  party.id !== client.party_id &&
                  !clientPrincipalIds.has(party.id) &&
                  party.status === 'active'
              );
              return (
                <article
                  key={client.id}
                  className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
                >
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <h3 className="text-lg font-semibold text-slate-950">
                        {principal?.display_name ?? 'Cliente sem nome'}
                      </h3>
                      <p className="mt-1 text-sm text-slate-600">
                        {portfolio?.processCount ?? 0} processo(s) ·{' '}
                        {portfolio?.noveltyCount ?? 0} com novidades ·{' '}
                        {statusLabel(client.status)}
                      </p>
                      <p className="mt-1 text-xs text-slate-500">
                        {portfolio?.notUpdatedCount ?? 0} não atualizado(s) ·{' '}
                        {portfolio?.failureCount ?? 0} com falha ·{' '}
                        {portfolio?.reviewCount ?? 0} em revisão
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-3 text-sm font-semibold">
                      <Link
                        href={`/app/processos?clientId=${client.id}`}
                        className="text-sky-700 hover:underline"
                      >
                        Ver processos
                      </Link>
                      {canMutate ? (
                        <Link
                          href={`/app/processos?clientId=${client.id}`}
                          className="text-emerald-700 hover:underline"
                        >
                          Adicionar processo
                        </Link>
                      ) : null}
                    </div>
                  </div>
                  <div className="mt-3 grid gap-2 text-xs text-slate-600 sm:grid-cols-2">
                    <p>
                      Última consulta:{' '}
                      {formatDate(portfolio?.lastConsultedAt ?? null)}
                    </p>
                    <p>
                      Última atualização da fonte:{' '}
                      {formatDate(portfolio?.lastSourceUpdatedAt ?? null)}
                    </p>
                  </div>
                  <div className="mt-4 divide-y divide-slate-100">
                    {!portfolio || portfolio.processes.length === 0 ? (
                      <p className="py-3 text-sm text-slate-500">
                        Nenhum processo cadastrado para este cliente.
                      </p>
                    ) : (
                      portfolio.processes.map((process) => (
                        <div
                          key={process.processId}
                          className="flex flex-wrap items-center justify-between gap-3 py-3"
                        >
                          <div className="min-w-0">
                            <p className="font-mono text-sm font-semibold text-slate-950 break-all">
                              {process.cnjNumber}
                            </p>
                            <p className="text-xs text-slate-600">
                              {process.tribunal} ·{' '}
                              {process.isPublic ? 'Público' : 'Sigiloso'} ·{' '}
                              {portfolioStateLabel(process)}
                            </p>
                            <p className="mt-1 text-xs text-slate-500">
                              Última consulta:{' '}
                              {formatDate(process.lastConsultedAt)}
                              {' · '}
                              Última atualização da fonte:{' '}
                              {formatDate(process.sourceUpdatedAt)}
                            </p>
                            {process.recentMovement ? (
                              <p className="mt-1 text-xs text-slate-600">
                                Movimentação recente:{' '}
                                {process.recentMovement.description ??
                                  'Registrada'}
                              </p>
                            ) : null}
                          </div>
                          {canMutate &&
                          process.isPublic &&
                          process.status === 'active' ? (
                            <RefreshProcessButton
                              processId={process.processId}
                              compact
                            />
                          ) : null}
                        </div>
                      ))
                    )}
                  </div>
                  <div className="mt-6 border-t border-slate-100 pt-5">
                    <h4 className="text-sm font-semibold text-slate-950">
                      Partes relacionadas
                    </h4>
                    <p className="mt-1 text-xs text-slate-600">
                      Toda relação nasce pendente e só um lawyer pode confirmar
                      ou rejeitar.
                    </p>
                    {canMutate && client.status === 'active' ? (
                      <form
                        action={async (formData) => {
                          'use server';
                          await createRelatedPartyAction(formData);
                        }}
                        className="mt-4 grid gap-3 rounded-lg bg-slate-50 p-4"
                      >
                        <input
                          type="hidden"
                          name="clientId"
                          value={client.id}
                        />
                        <label className="text-sm font-medium text-slate-700">
                          Parte relacionada
                          <select
                            name="partyId"
                            required
                            className="mt-1 w-full rounded border border-slate-300 bg-white px-3 py-2"
                          >
                            {candidates.map((party) => (
                              <option key={party.id} value={party.id}>
                                {party.display_name} · {shortId(party.id)} ·{' '}
                                {party.party_type}
                              </option>
                            ))}
                          </select>
                        </label>
                        <label className="text-sm font-medium text-slate-700">
                          Tipo
                          <select
                            name="relationType"
                            defaultValue="representative"
                            className="mt-1 w-full rounded border border-slate-300 bg-white px-3 py-2"
                          >
                            {relationTypes.map((type) => (
                              <option key={type} value={type}>
                                {type}
                              </option>
                            ))}
                          </select>
                        </label>
                        <label className="text-sm font-medium text-slate-700">
                          Observação
                          <input
                            name="notes"
                            maxLength={1000}
                            className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
                          />
                        </label>
                        <button
                          className="rounded bg-sky-700 px-3 py-2 font-semibold text-white"
                          type="submit"
                        >
                          Criar relação pendente
                        </button>
                      </form>
                    ) : null}
                    <div className="mt-4 space-y-3">
                      {clientRelations.length === 0 ? (
                        <p className="text-sm text-slate-500">
                          Nenhuma parte relacionada cadastrada.
                        </p>
                      ) : (
                        clientRelations.map((relation) => {
                          const related = partyById.get(relation.party_id);
                          return (
                            <div
                              key={relation.id}
                              className="rounded-lg border border-slate-200 p-4"
                            >
                              <div className="flex flex-wrap items-center justify-between gap-3">
                                <div>
                                  <p className="font-medium text-slate-900">
                                    {related?.display_name ??
                                      'Parte não encontrada'}{' '}
                                    <span className="font-mono text-xs text-slate-500">
                                      ({shortId(relation.party_id)})
                                    </span>
                                  </p>
                                  <p className="text-sm text-slate-600">
                                    {relation.relation_type} ·{' '}
                                    {statusLabel(relation.status)} ·
                                    confirmação:{' '}
                                    <strong>
                                      {confirmationLabel(
                                        relation.confirmation_status
                                      )}
                                    </strong>
                                  </p>
                                  {relation.confirmed_at ? (
                                    <p className="text-xs text-slate-500">
                                      Decisão em{' '}
                                      {new Date(
                                        relation.confirmed_at
                                      ).toLocaleString('pt-BR')}
                                    </p>
                                  ) : null}
                                </div>
                                {canConfirm &&
                                relation.status === 'active' &&
                                relation.confirmation_status === 'pending' ? (
                                  <div className="flex gap-2">
                                    <form
                                      action={async (formData) => {
                                        'use server';
                                        await confirmRelatedPartyAction(
                                          formData
                                        );
                                      }}
                                    >
                                      <input
                                        type="hidden"
                                        name="relationId"
                                        value={relation.id}
                                      />
                                      <button
                                        className="rounded bg-emerald-700 px-3 py-1 text-xs font-semibold text-white"
                                        type="submit"
                                      >
                                        Confirmar
                                      </button>
                                    </form>
                                    <form
                                      action={async (formData) => {
                                        'use server';
                                        await rejectRelatedPartyAction(
                                          formData
                                        );
                                      }}
                                    >
                                      <input
                                        type="hidden"
                                        name="relationId"
                                        value={relation.id}
                                      />
                                      <button
                                        className="rounded bg-rose-700 px-3 py-1 text-xs font-semibold text-white"
                                        type="submit"
                                      >
                                        Rejeitar
                                      </button>
                                    </form>
                                  </div>
                                ) : null}
                              </div>
                              {canMutate && relation.status === 'active' ? (
                                <form
                                  action={async (formData) => {
                                    'use server';
                                    await deactivateRelatedPartyAction(
                                      formData
                                    );
                                  }}
                                  className="mt-3"
                                >
                                  <input
                                    type="hidden"
                                    name="id"
                                    value={relation.id}
                                  />
                                  <button
                                    className="rounded border border-slate-300 px-2 py-1 text-xs text-slate-700"
                                    type="submit"
                                  >
                                    Desativar relação
                                  </button>
                                </form>
                              ) : null}
                            </div>
                          );
                        })
                      )}
                    </div>
                  </div>
                </article>
              );
            })}
          </div>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-950">
              Partes do escritório
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              A referência curta distingue homônimos sem usar o nome como
              identidade.
            </p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="bg-slate-50 text-slate-600">
                <tr>
                  <th className="px-6 py-3">Nome</th>
                  <th className="px-6 py-3">ID</th>
                  <th className="px-6 py-3">Tipo</th>
                  <th className="px-6 py-3">Status</th>
                  <th className="px-6 py-3">Ações</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200">
                {(parties ?? []).map((party) => (
                  <tr key={party.id}>
                    <td className="px-6 py-4 font-medium text-slate-900">
                      {party.display_name}
                    </td>
                    <td className="px-6 py-4 font-mono text-xs text-slate-600">
                      {shortId(party.id)}
                    </td>
                    <td className="px-6 py-4 text-slate-600">
                      {party.party_type}
                    </td>
                    <td className="px-6 py-4 text-slate-600">
                      {statusLabel(party.status)}
                    </td>
                    <td className="px-6 py-4">
                      {canMutate && party.status === 'active' ? (
                        <div className="flex flex-wrap gap-2">
                          <form
                            action={async (formData) => {
                              'use server';
                              await updatePartyAction(formData);
                            }}
                          >
                            <input type="hidden" name="id" value={party.id} />
                            <input
                              type="hidden"
                              name="displayName"
                              value={party.display_name}
                            />
                            <input
                              type="hidden"
                              name="partyType"
                              value={party.party_type}
                            />
                            <button
                              className="rounded border px-2 py-1 text-xs"
                              type="submit"
                            >
                              Salvar dados atuais
                            </button>
                          </form>
                          <form
                            action={async (formData) => {
                              'use server';
                              await deactivatePartyAction(formData);
                            }}
                          >
                            <input type="hidden" name="id" value={party.id} />
                            <button
                              className="rounded border border-rose-200 px-2 py-1 text-xs text-rose-700"
                              type="submit"
                            >
                              Desativar
                            </button>
                          </form>
                        </div>
                      ) : (
                        '—'
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </main>
  );
}
