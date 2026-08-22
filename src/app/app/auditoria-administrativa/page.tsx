import Link from 'next/link';
import { listAdministrativeAudit } from '@/lib/audit';
import { requirePermission } from '@/lib/auth/guards';
import { ExportAuditButton } from './export-audit-button';

function formatDate(value: string): string {
  return new Date(value).toLocaleString('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  });
}

export default async function AdministrativeAuditPage() {
  const { office } = await requirePermission('view_administrative_audit');
  const entries = await listAdministrativeAudit({ limit: 100 });

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
            href="/app/configuracoes"
          >
            Configurações do escritório
          </Link>
        </div>
      </nav>

      <section className="mx-auto max-w-6xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="text-sm font-semibold text-sky-700">
              Controle e segurança
            </p>
            <h1 className="mt-2 text-3xl font-semibold tracking-tight text-slate-950">
              Auditoria administrativa
            </h1>
            <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-600">
              Eventos administrativos do escritório {office.name}. A trilha é
              somente de acréscimo e não inclui tokens, senhas ou payloads
              brutos.
            </p>
          </div>
          <ExportAuditButton />
        </div>

        <section className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
          <table className="min-w-[760px] divide-y divide-slate-200 text-left text-sm">
            <caption className="sr-only">
              Eventos administrativos recentes
            </caption>
            <thead className="bg-slate-50">
              <tr>
                <th className="px-4 py-3 font-semibold text-slate-900">Data</th>
                <th className="px-4 py-3 font-semibold text-slate-900">Ação</th>
                <th className="px-4 py-3 font-semibold text-slate-900">
                  Recurso
                </th>
                <th className="px-4 py-3 font-semibold text-slate-900">
                  Detalhes
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {entries.map((entry) => (
                <tr key={entry.id} className="align-top">
                  <td className="whitespace-nowrap px-4 py-3 text-slate-600">
                    {formatDate(entry.created_at)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 font-medium text-slate-900">
                    {entry.action}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-slate-600">
                    {entry.entity_type}
                  </td>
                  <td className="max-w-md px-4 py-3 font-mono text-xs text-slate-600">
                    {JSON.stringify(entry.metadata)}
                  </td>
                </tr>
              ))}
              {!entries.length && (
                <tr>
                  <td
                    className="px-4 py-8 text-center text-slate-500"
                    colSpan={4}
                  >
                    Nenhum evento administrativo registrado.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>
      </section>
    </main>
  );
}
