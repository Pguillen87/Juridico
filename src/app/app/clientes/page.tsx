import { requireAuthenticatedProfile } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { createClientAction, createPartyAction } from './actions';

export default async function ClientsPage() {
  await requireAuthenticatedProfile();
  const supabase = await createClient();
  const { data: clients, error } = await supabase
    .from('client')
    .select('id,status,party_id')
    .order('created_at', { ascending: false });
  if (error) throw new Error('Não foi possível carregar os clientes.');
  const ids = (clients ?? []).map((client) => client.party_id);
  const { data: parties } = ids.length
    ? await supabase
        .from('party')
        .select('id,display_name,party_type')
        .in('id', ids)
    : {
        data: [] as { id: string; display_name: string; party_type: string }[],
      };
  const partyById = new Map((parties ?? []).map((party) => [party.id, party]));
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
          <p className="mt-2 max-w-2xl text-slate-600">
            Cadastre entidades do seu escritório. Nomes iguais permanecem
            registros distintos e nenhuma relação é confirmada automaticamente.
          </p>
        </header>
        <section className="grid gap-6 lg:grid-cols-2">
          <form
            action={async (formData) => {
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
              Clientes do escritório
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              A busca e os detalhes permanecem isolados por office e respeitam
              RLS.
            </p>
          </div>
          {clients?.length ? (
            <div className="overflow-x-auto">
              <table className="min-w-full text-left text-sm">
                <thead className="bg-slate-50 text-slate-600">
                  <tr>
                    <th className="px-6 py-3 font-semibold">Nome</th>
                    <th className="px-6 py-3 font-semibold">Tipo</th>
                    <th className="px-6 py-3 font-semibold">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {clients.map((client) => {
                    const party = partyById.get(client.party_id);
                    return (
                      <tr key={client.id}>
                        <td className="px-6 py-4 font-medium text-slate-900">
                          {party?.display_name ?? 'Parte não encontrada'}
                        </td>
                        <td className="px-6 py-4 text-slate-600">
                          {party?.party_type ?? '—'}
                        </td>
                        <td className="px-6 py-4 text-slate-600">
                          {client.status === 'active' ? 'Ativo' : 'Inativo'}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="p-6 text-sm text-slate-600">
              Nenhum cliente cadastrado neste escritório.
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
