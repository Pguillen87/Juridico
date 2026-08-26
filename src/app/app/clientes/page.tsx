import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import {
  confirmRelatedPartyAction,
  createClientAction,
  createPartyAction,
  createRelatedPartyAction,
  deactivateClientAction,
  deactivatePartyAction,
  deactivateRelatedPartyAction,
  rejectRelatedPartyAction,
  updateClientAction,
  updatePartyAction,
} from './actions';

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

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between px-4">
          <a href="/app" className="font-semibold text-slate-950">
            Juridico
          </a>
          <span className="text-sm text-slate-600">Clientes e partes</span>
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

        <section className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-950">
              Clientes e partes relacionadas
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              Toda relação nasce pendente e só um lawyer pode confirmar ou
              rejeitar.
            </p>
          </div>
          <div className="divide-y divide-slate-200">
            {(clients ?? []).map((client) => {
              const principal = partyById.get(client.party_id);
              const clientRelations = relationsByClient.get(client.id) ?? [];
              const candidates = (parties ?? []).filter(
                (party) =>
                  party.id !== client.party_id && party.status === 'active'
              );
              return (
                <article key={client.id} className="p-6">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div>
                      <h3 className="text-lg font-semibold text-slate-950">
                        {principal?.display_name ?? 'Parte não encontrada'}
                      </h3>
                      <p className="text-sm text-slate-600">
                        Parte principal:{' '}
                        <span className="font-mono">
                          {principal ? shortId(principal.id) : '—'}
                        </span>{' '}
                        · {statusLabel(client.status)}
                      </p>
                    </div>
                    {canMutate && client.status === 'active' ? (
                      <div className="flex gap-2">
                        <form
                          action={async (formData) => {
                            'use server';
                            await updateClientAction(formData);
                          }}
                        >
                          <input type="hidden" name="id" value={client.id} />
                          <input type="hidden" name="status" value="active" />
                          <button
                            className="rounded border px-2 py-1 text-xs"
                            type="submit"
                          >
                            Salvar status
                          </button>
                        </form>
                        <form
                          action={async (formData) => {
                            'use server';
                            await deactivateClientAction(formData);
                          }}
                        >
                          <input type="hidden" name="id" value={client.id} />
                          <button
                            className="rounded border border-rose-200 px-2 py-1 text-xs text-rose-700"
                            type="submit"
                          >
                            Desativar cliente
                          </button>
                        </form>
                      </div>
                    ) : null}
                  </div>
                  {canMutate && client.status === 'active' ? (
                    <form
                      action={async (formData) => {
                        'use server';
                        await createRelatedPartyAction(formData);
                      }}
                      className="mt-5 grid gap-3 rounded-lg bg-slate-50 p-4 md:grid-cols-4"
                    >
                      <input type="hidden" name="clientId" value={client.id} />
                      <label className="text-sm font-medium text-slate-700 md:col-span-2">
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
                        className="rounded bg-sky-700 px-3 py-2 font-semibold text-white md:col-span-4"
                        type="submit"
                      >
                        Criar relação pendente
                      </button>
                    </form>
                  ) : null}
                  <div className="mt-5 space-y-3">
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
                                  {statusLabel(relation.status)} · confirmação:{' '}
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
                                      await confirmRelatedPartyAction(formData);
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
                                      await rejectRelatedPartyAction(formData);
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
                                  await deactivateRelatedPartyAction(formData);
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
                </article>
              );
            })}
          </div>
        </section>
      </div>
    </main>
  );
}
