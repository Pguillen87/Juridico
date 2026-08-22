import Link from 'next/link';
import { requireOwnerProfile, roleLabel } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { InviteForm } from './invite-form';
import { UserRowActions } from './user-row-actions';

export default async function UsersPage() {
  const { profile, office } = await requireOwnerProfile();
  const supabase = await createClient();

  const { data: users, error } = await supabase
    .from('user_profile')
    .select('id, name, role, is_active, is_owner')
    .eq('office_id', profile.office_id)
    .order('name');

  if (error) {
    throw new Error('Não foi possível carregar a lista de usuários.');
  }

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6 lg:px-8">
          <Link
            className="text-sm font-medium text-sky-700 hover:text-sky-900"
            href="/app"
          >
            ← Voltar para o painel
          </Link>
          <div className="flex items-center gap-4 text-sm">
            <Link
              className="text-slate-600 hover:text-slate-950"
              href="/app/configuracoes"
            >
              Configurações do escritório
            </Link>
            <Link
              className="text-slate-600 hover:text-slate-950"
              href="/app/auditoria-administrativa"
            >
              Auditoria administrativa
            </Link>
          </div>
        </div>
      </nav>

      <section className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="mb-8">
          <p className="text-sm font-semibold text-sky-700">Administração</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-slate-950">
            Usuários do escritório
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-600">
            Gerencie o acesso da sua equipe em {office.name}. Inativar preserva
            o histórico; não há exclusão definitiva nesta etapa.
          </p>
        </div>

        <div className="grid gap-8 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
              <table className="min-w-[760px] divide-y divide-slate-200 text-left text-sm">
                <caption className="sr-only">Membros do escritório</caption>
                <thead className="bg-slate-50">
                  <tr>
                    <th className="px-4 py-3 font-semibold text-slate-900">
                      Nome
                    </th>
                    <th className="px-4 py-3 font-semibold text-slate-900">
                      Papel
                    </th>
                    <th className="px-4 py-3 font-semibold text-slate-900">
                      Status
                    </th>
                    <th className="px-4 py-3 font-semibold text-slate-900">
                      Administrador
                    </th>
                    <th className="px-4 py-3 font-semibold text-slate-900">
                      Ações
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {users?.map((user) => (
                    <tr
                      key={user.id}
                      className="align-top transition hover:bg-slate-50"
                    >
                      <td className="whitespace-nowrap px-4 py-3 font-medium text-slate-900">
                        {user.name} {user.id === profile.id ? '(Você)' : ''}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-slate-600">
                        {roleLabel(user.role)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3">
                        <span
                          className={`inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ${
                            user.is_active
                              ? 'bg-emerald-50 text-emerald-700 ring-1 ring-inset ring-emerald-600/20'
                              : 'bg-red-50 text-red-700 ring-1 ring-inset ring-red-600/20'
                          }`}
                        >
                          {user.is_active ? 'Ativo' : 'Inativo'}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-slate-600">
                        {user.is_owner ? 'Sim' : 'Não'}
                      </td>
                      <td className="px-4 py-3">
                        <UserRowActions
                          currentProfileId={profile.id}
                          user={user}
                        />
                      </td>
                    </tr>
                  ))}
                  {!users?.length && (
                    <tr>
                      <td
                        className="px-4 py-4 text-center text-slate-500"
                        colSpan={5}
                      >
                        Nenhum usuário encontrado.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>

          <div>
            <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
              <h2 className="text-base font-semibold text-slate-950">
                Convidar membro
              </h2>
              <p className="mt-1 text-sm text-slate-600">
                O usuário receberá um link por e-mail para definir sua senha.
              </p>
              <div className="mt-6">
                <InviteForm />
              </div>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
