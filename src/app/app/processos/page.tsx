import Link from 'next/link';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import {
  confirmProcessPartyAction,
  createProcessAction,
  createProcessPartyAction,
  deactivateProcessPartyAction,
  rejectProcessPartyAction,
} from './actions';
import { ImportCsvForm } from './import-csv-form';

const processRoles = [
  'client',
  'plaintiff',
  'defendant',
  'representative',
  'interested_party',
  'other',
] as const;

function shortId(id: string) {
  return id.slice(0, 8);
}

function statusLabel(status: string) {
  return status === 'active' ? 'Ativo' : 'Inativo';
}

function confirmationLabel(status: string) {
  if (status === 'confirmed') return 'Confirmado';
  if (status === 'rejected') return 'Rejeitado';
  return 'Pendente';
}

export default async function ProcessesPage() {
  const { profile } = await requirePermission('view_operational_data');
  const canMutate = profile.role === 'lawyer' || profile.role === 'operator';
  const canConfirm = profile.role === 'lawyer';
  const supabase = await createClient();
  const [
    { data: clients, error: clientsError },
    { data: parties, error: partiesError },
    { data: processes, error: processesError },
    { data: relations, error: relationsError },
  ] = await Promise.all([
    supabase
      .from('client')
      .select('id,party_id,status')
      .eq('status', 'active')
      .order('created_at', { ascending: false }),
    supabase
      .from('party')
      .select('id,display_name,party_type,status')
      .eq('status', 'active')
      .order('display_name'),
    supabase
      .from('legal_process')
      .select(
        'id,client_id,cnj_number,tribunal,system,is_public,monitoring_status,status,created_at'
      )
      .order('created_at', { ascending: false }),
    supabase
      .from('process_party')
      .select(
        'id,process_id,party_id,role_in_process,source,confirmation_status,confirmed_at,status,notes'
      )
      .order('created_at', { ascending: false }),
  ]);
  if (clientsError || partiesError || processesError || relationsError)
    throw new Error('Não foi possível carregar os dados de processos.');

  const partyById = new Map((parties ?? []).map((party) => [party.id, party]));
  const clientById = new Map(
    (clients ?? []).map((client) => [client.id, client])
  );
  const relationsByProcess = new Map<string, typeof relations>();
  for (const relation of relations ?? []) {
    const current = relationsByProcess.get(relation.process_id) ?? [];
    current.push(relation);
    relationsByProcess.set(relation.process_id, current);
  }

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between px-4">
          <div>
            <Link href="/app" className="font-semibold text-slate-950">
              Juridico
            </Link>
            <p className="text-xs text-slate-500">Processos e importação</p>
          </div>
          <div className="flex gap-4 text-sm">
            <Link className="text-sky-700 hover:underline" href="/app/clientes">
              Clientes e partes
            </Link>
            <Link className="text-slate-600 hover:underline" href="/app">
              Área protegida
            </Link>
          </div>
        </div>
      </nav>

      <div className="mx-auto max-w-7xl space-y-8 px-4 py-10 sm:px-6 lg:px-8">
        <header>
          <p className="text-sm font-semibold uppercase tracking-wide text-sky-700">
            US-006 · US-007 · US-008 · US-009 · US-010 · US-011
          </p>
          <h1 className="mt-2 text-3xl font-bold text-slate-950">
            Processos e importação CSV
          </h1>
          <p className="mt-2 max-w-3xl text-slate-600">
            Cadastre processos com CNJ canônico, associe partes por ID e revise
            vínculos pendentes. Nesta fase, monitoramento permanece pausado;
            nenhuma consulta externa é executada.
          </p>
        </header>

        {canMutate ? (
          <section className="grid gap-6 lg:grid-cols-2">
            <form
              action={async (formData) => {
                'use server';
                await createProcessAction(formData);
              }}
              className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
            >
              <h2 className="text-lg font-semibold text-slate-950">
                Novo processo
              </h2>
              <p className="mt-1 text-sm text-slate-600">
                O CNJ é validado novamente no PostgreSQL e o processo nasce com
                monitoramento pausado.
              </p>
              <div className="mt-5 space-y-4">
                <label className="block text-sm font-medium text-slate-700">
                  Cliente
                  <select
                    name="clientId"
                    required
                    className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
                  >
                    <option value="">Selecione pelo ID</option>
                    {(clients ?? []).map((client) => {
                      const principal = partyById.get(client.party_id);
                      return (
                        <option key={client.id} value={client.id}>
                          {principal?.display_name ?? 'Cliente'} ·{' '}
                          {shortId(client.id)}
                        </option>
                      );
                    })}
                  </select>
                </label>
                <label className="block text-sm font-medium text-slate-700">
                  Número CNJ
                  <input
                    name="cnj"
                    required
                    placeholder="0004453-12.2026.8.16.0000"
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  />
                </label>
                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="block text-sm font-medium text-slate-700">
                    Tribunal
                    <input
                      name="tribunal"
                      required
                      maxLength={200}
                      placeholder="Tribunal de Justiça"
                      className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                    />
                  </label>
                  <label className="block text-sm font-medium text-slate-700">
                    Sistema
                    <input
                      name="system"
                      maxLength={120}
                      placeholder="PJe"
                      className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                    />
                  </label>
                </div>
                <label className="block text-sm font-medium text-slate-700">
                  Publicidade
                  <select
                    name="isPublic"
                    defaultValue="public"
                    className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
                  >
                    <option value="public">Público</option>
                    <option value="private">Sigiloso</option>
                  </select>
                </label>
                <button
                  className="rounded-md bg-sky-700 px-4 py-2 font-semibold text-white hover:bg-sky-800"
                  type="submit"
                >
                  Cadastrar processo
                </button>
              </div>
            </form>
            <ImportCsvForm />
          </section>
        ) : null}

        <section className="rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-950">
          <strong>Monitoramento nesta fase:</strong> processos são criados com
          estado <code>paused</code>. Não há provider, scheduler, fila ou ação
          de ativação real. A US-011 permanece parcial/deferida.
        </section>

        <section className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-200 p-6">
            <h2 className="text-lg font-semibold text-slate-950">
              Processos cadastrados
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              A referência curta do processo, cliente e parte mantém IDs
              explícitos para evitar ambiguidades entre homônimos.
            </p>
          </div>
          <div className="divide-y divide-slate-200">
            {(processes ?? []).length === 0 ? (
              <p className="p-6 text-sm text-slate-500">
                Nenhum processo cadastrado.
              </p>
            ) : null}
            {(processes ?? []).map((process) => {
              const client = clientById.get(process.client_id);
              const principal = client
                ? partyById.get(client.party_id)
                : undefined;
              const processRelations = relationsByProcess.get(process.id) ?? [];
              return (
                <article key={process.id} className="p-6">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div>
                      <h3 className="font-mono text-lg font-semibold text-slate-950">
                        {process.cnj_number}
                      </h3>
                      <p className="mt-1 text-sm text-slate-600">
                        Processo {shortId(process.id)} · {process.tribunal}
                        {process.system ? ` · ${process.system}` : ''}
                      </p>
                      <p className="text-sm text-slate-600">
                        Cliente: {principal?.display_name ?? 'não encontrado'} ·{' '}
                        {client ? shortId(client.id) : '—'} ·{' '}
                        {process.is_public ? 'Público' : 'Sigiloso'} ·{' '}
                        {statusLabel(process.status)}
                      </p>
                      <p className="mt-1 text-xs font-semibold uppercase tracking-wide text-amber-700">
                        Monitoramento: {process.monitoring_status}
                      </p>
                    </div>
                  </div>

                  {canMutate && process.status === 'active' ? (
                    <form
                      action={async (formData) => {
                        'use server';
                        await createProcessPartyAction(formData);
                      }}
                      className="mt-5 grid gap-3 rounded-lg bg-slate-50 p-4 md:grid-cols-4"
                    >
                      <input
                        type="hidden"
                        name="processId"
                        value={process.id}
                      />
                      <label className="text-sm font-medium text-slate-700 md:col-span-2">
                        Parte
                        <select
                          name="partyId"
                          required
                          className="mt-1 w-full rounded border border-slate-300 bg-white px-3 py-2"
                        >
                          <option value="">Selecione pelo ID</option>
                          {(parties ?? []).map((party) => (
                            <option key={party.id} value={party.id}>
                              {party.display_name} · {shortId(party.id)}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="text-sm font-medium text-slate-700">
                        Papel
                        <select
                          name="role"
                          defaultValue="plaintiff"
                          className="mt-1 w-full rounded border border-slate-300 bg-white px-3 py-2"
                        >
                          {processRoles.map((role) => (
                            <option key={role} value={role}>
                              {role}
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
                        Criar vínculo pendente
                      </button>
                    </form>
                  ) : null}

                  <div className="mt-5 space-y-3">
                    {processRelations.length === 0 ? (
                      <p className="text-sm text-slate-500">
                        Nenhuma parte vinculada.
                      </p>
                    ) : null}
                    {processRelations.map((relation) => {
                      const party = partyById.get(relation.party_id);
                      return (
                        <div
                          key={relation.id}
                          className="rounded-lg border border-slate-200 p-4"
                        >
                          <div className="flex flex-wrap items-center justify-between gap-3">
                            <div>
                              <p className="font-medium text-slate-900">
                                {party?.display_name ?? 'Parte não encontrada'}{' '}
                                <span className="font-mono text-xs text-slate-500">
                                  ({shortId(relation.party_id)})
                                </span>
                              </p>
                              <p className="text-sm text-slate-600">
                                {relation.role_in_process} · fonte{' '}
                                {relation.source} · confirmação:{' '}
                                <strong>
                                  {confirmationLabel(
                                    relation.confirmation_status
                                  )}
                                </strong>{' '}
                                · {statusLabel(relation.status)}
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
                                    await confirmProcessPartyAction(formData);
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
                                    await rejectProcessPartyAction(formData);
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
                                await deactivateProcessPartyAction(formData);
                              }}
                              className="mt-3"
                            >
                              <input
                                type="hidden"
                                name="relationId"
                                value={relation.id}
                              />
                              <button
                                className="rounded border border-slate-300 px-2 py-1 text-xs text-slate-700"
                                type="submit"
                              >
                                Desativar vínculo
                              </button>
                            </form>
                          ) : null}
                        </div>
                      );
                    })}
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
