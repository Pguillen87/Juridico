import Link from 'next/link';
import { LogoutButton } from '@/components/auth/logout-button';
import { requireAuthenticatedProfile, roleLabel } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { getClientPortfolioReadModels } from '@/lib/clients/portfolio';

export default async function AppPage() {
  const { user, profile, office } = await requireAuthenticatedProfile();
  const supabase = await createClient();
  const portfolios = await getClientPortfolioReadModels(supabase);
  const portfolioTotals = portfolios.reduce(
    (totals, portfolio) => ({
      processCount: totals.processCount + portfolio.processCount,
      noveltyCount: totals.noveltyCount + portfolio.noveltyCount,
      attentionCount:
        totals.attentionCount +
        portfolio.notUpdatedCount +
        portfolio.failureCount +
        portfolio.reviewCount,
    }),
    { processCount: 0, noveltyCount: 0, attentionCount: 0 }
  );

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6 lg:px-8">
          <div className="flex items-center gap-6">
            <Link href="/app" className="group">
              <p className="text-sm font-semibold uppercase tracking-[0.18em] text-sky-700 group-hover:text-sky-800">
                Juridico
              </p>
              <p className="text-xs text-slate-500">Início</p>
            </Link>
            <div className="hidden md:flex items-center gap-4 text-sm font-medium">
              <Link
                className="text-slate-700 hover:text-sky-700"
                href="/app/processos"
              >
                Processos
              </Link>
              <Link
                className="text-slate-700 hover:text-sky-700"
                href="/app/clientes"
              >
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
          <div className="flex items-center gap-5">
            <span className="hidden text-sm text-slate-600 sm:inline">
              {user.email}
            </span>
            <LogoutButton />
          </div>
        </div>
      </nav>

      <section className="mx-auto max-w-6xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="mb-8">
          <p className="text-sm font-semibold text-sky-700">Visão geral</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-slate-950">
            Bem-vindo, {profile.name}
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-600">
            Esta área só fica disponível enquanto o seu perfil e o escritório
            estiverem ativos.
          </p>
        </div>

        <div className="grid gap-5 md:grid-cols-3">
          <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <p className="text-sm text-slate-500">Escritório</p>
            <p className="mt-2 text-lg font-semibold text-slate-950">
              {office.name}
            </p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <p className="text-sm text-slate-500">Papel</p>
            <p className="mt-2 text-lg font-semibold text-slate-950">
              {roleLabel(profile.role)}
            </p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <p className="text-sm text-slate-500">Permissão administrativa</p>
            <p className="mt-2 text-lg font-semibold text-slate-950">
              {profile.is_owner ? 'Administrador' : 'Usuário'}
            </p>
          </div>
        </div>

        {profile.role !== 'auditor' ? (
          <section className="mt-8 space-y-4">
            <div>
              <h2 className="text-2xl font-semibold text-slate-950">
                Carteira
              </h2>
              <p className="mt-1 text-sm text-slate-600">
                Acompanhe clientes, processos conhecidos e as próximas
                atualizações.
              </p>
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {[
                ['Clientes', portfolios.length],
                ['Processos cadastrados', portfolioTotals.processCount],
                ['Processos com novidades', portfolioTotals.noveltyCount],
                [
                  'Precisam de atualização/revisão',
                  portfolioTotals.attentionCount,
                ],
              ].map(([label, value]) => (
                <div
                  key={label}
                  className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
                >
                  <p className="text-sm text-slate-500">{label}</p>
                  <p className="mt-2 text-3xl font-semibold text-slate-950">
                    {value}
                  </p>
                </div>
              ))}
            </div>
          </section>
        ) : null}

        {profile.role !== 'auditor' ? (
          <div className="mt-8 grid gap-5 md:grid-cols-2 lg:grid-cols-3">
            <div className="rounded-xl border border-sky-200 bg-sky-50 p-6">
              <h2 className="text-lg font-semibold text-slate-950">
                Operação de processos
              </h2>
              <p className="mt-2 text-sm leading-6 text-slate-600">
                Cadastre processos, revise vínculos pendentes e importe um CSV
                com prévia transacional.
              </p>
              <Link
                className="mt-5 inline-flex rounded-md bg-sky-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-sky-800"
                href="/app/processos"
              >
                Abrir processos
              </Link>
            </div>
            <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-6">
              <h2 className="text-lg font-semibold text-slate-950">
                Clientes e partes
              </h2>
              <p className="mt-2 text-sm leading-6 text-slate-600">
                Cadastre clientes, partes relacionadas e gerencie vínculos do
                seu escritório.
              </p>
              <Link
                className="mt-5 inline-flex rounded-md bg-emerald-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-800"
                href="/app/clientes"
              >
                Abrir clientes
              </Link>
            </div>
            <div className="rounded-xl border border-rose-200 bg-rose-50 p-6">
              <h2 className="text-lg font-semibold text-slate-950">
                Central de falhas
              </h2>
              <p className="mt-2 text-sm leading-6 text-slate-600">
                Consulte falhas persistidas, tentativas, histórico operacional e
                notificações internas sintéticas.
              </p>
              <Link
                className="mt-5 inline-flex rounded-md bg-rose-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-800"
                href="/app/falhas"
              >
                Abrir central de falhas
              </Link>
            </div>
            {profile.role === 'lawyer' || profile.role === 'reviewer' ? (
              <div className="rounded-xl border border-violet-200 bg-violet-50 p-6">
                <h2 className="text-lg font-semibold text-slate-950">
                  Relatórios semanais
                </h2>
                <p className="mt-2 text-sm leading-6 text-slate-600">
                  Revise versões semanais congeladas, acompanhe evidências e
                  mantenha aprovação separada de qualquer envio.
                </p>
                <Link
                  className="mt-5 inline-flex rounded-md bg-violet-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-violet-800"
                  href="/app/relatorios"
                >
                  Abrir relatórios
                </Link>
              </div>
            ) : null}
          </div>
        ) : null}

        {profile.is_owner || profile.role === 'auditor' ? (
          <div className="mt-8 rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-slate-950">
              Administração
            </h2>
            <p className="mt-2 text-sm leading-6 text-slate-600">
              {profile.is_owner
                ? 'Convide e acompanhe os usuários do seu escritório em uma área separada.'
                : 'Consulte a trilha de auditoria administrativa do seu escritório.'}
            </p>
            <div className="mt-5 flex flex-wrap gap-3">
              {profile.is_owner ? (
                <>
                  <Link
                    className="inline-flex rounded-md bg-sky-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-sky-800"
                    href="/app/usuarios"
                  >
                    Gerenciar usuários
                  </Link>
                  <Link
                    className="inline-flex rounded-md border border-slate-300 px-4 py-2.5 text-sm font-semibold text-slate-700 transition hover:bg-slate-50"
                    href="/app/configuracoes"
                  >
                    Configurações do escritório
                  </Link>
                </>
              ) : null}
              <Link
                className="inline-flex rounded-md border border-slate-300 px-4 py-2.5 text-sm font-semibold text-slate-700 transition hover:bg-slate-50"
                href="/app/auditoria-administrativa"
              >
                Auditoria administrativa
              </Link>
            </div>
          </div>
        ) : null}
      </section>
    </main>
  );
}
