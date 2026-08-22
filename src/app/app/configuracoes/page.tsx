import Link from 'next/link';
import { requireOwnerProfile } from '@/lib/auth/guards';
import { OfficeNameForm } from './office-name-form';

export default async function OfficeSettingsPage() {
  const { office } = await requireOwnerProfile();

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-6xl flex-wrap items-center gap-4 px-4 py-3 sm:px-6 lg:px-8">
          <Link
            className="text-sm font-medium text-sky-700 hover:text-sky-900"
            href="/app"
          >
            ← Voltar para o painel
          </Link>
          <Link
            className="text-sm text-slate-600 hover:text-slate-950"
            href="/app/usuarios"
          >
            Usuários
          </Link>
          <Link
            className="text-sm text-slate-600 hover:text-slate-950"
            href="/app/auditoria-administrativa"
          >
            Auditoria administrativa
          </Link>
        </div>
      </nav>

      <section className="mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="mb-8">
          <p className="text-sm font-semibold text-sky-700">Administração</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-slate-950">
            Configurações do escritório
          </h1>
          <p className="mt-2 text-sm leading-6 text-slate-600">
            Altere apenas o nome do escritório. O status é informativo e não
            pode ser desativado por esta tela.
          </p>
        </div>

        <div className="space-y-6">
          <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 className="text-base font-semibold text-slate-950">
              Identificação
            </h2>
            <div className="mt-5">
              <OfficeNameForm currentName={office.name} />
            </div>
          </section>

          <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 className="text-base font-semibold text-slate-950">
              Status do escritório
            </h2>
            <dl className="mt-4 grid gap-4 sm:grid-cols-2">
              <div>
                <dt className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Status atual
                </dt>
                <dd className="mt-1 text-sm font-medium text-emerald-700">
                  {office.is_active ? 'Ativo' : 'Inativo'}
                </dd>
              </div>
              <div>
                <dt className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Regra desta fase
                </dt>
                <dd className="mt-1 text-sm text-slate-700">
                  Sem desativação, troca de ID ou movimentação de membros.
                </dd>
              </div>
            </dl>
          </section>
        </div>
      </section>
    </main>
  );
}
