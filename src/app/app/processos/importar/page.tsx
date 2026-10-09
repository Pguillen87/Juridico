import Link from 'next/link';
import { requirePermission } from '@/lib/auth/guards';
import { ImportCsvForm } from '../import-csv-form';

export default async function ImportProcessesPage() {
  await requirePermission('create_process');

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-5xl items-center justify-between px-4">
          <Link href="/app/processos" className="font-semibold text-slate-950">
            Processos
          </Link>
          <Link
            href="/app/processos"
            className="text-sm font-semibold text-sky-700 hover:underline"
          >
            Voltar para a carteira
          </Link>
        </div>
      </nav>
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
        <header className="mb-6">
          <h1 className="text-2xl font-bold text-slate-950">
            Importar carteira
          </h1>
          <p className="mt-1 text-sm text-slate-600">
            Use esta área apenas quando precisar incluir vários processos por
            arquivo CSV.
          </p>
        </header>
        <ImportCsvForm />
      </div>
    </main>
  );
}
