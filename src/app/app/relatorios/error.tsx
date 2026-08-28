'use client';

import Link from 'next/link';

export default function ReportsError({ reset }: { reset: () => void }) {
  return (
    <main className="min-h-screen bg-slate-100 p-6">
      <section className="mx-auto max-w-2xl rounded-xl border border-rose-200 bg-white p-6 shadow-sm">
        <h1 className="text-xl font-semibold text-slate-950">
          Não foi possível carregar os relatórios
        </h1>
        <p className="mt-2 text-sm text-slate-600">
          A consulta falhou de forma segura. Nenhum fato foi alterado.
        </p>
        <div className="mt-5 flex flex-wrap gap-3">
          <button
            type="button"
            onClick={reset}
            className="rounded-md bg-slate-900 px-4 py-2 font-semibold text-white hover:bg-slate-800"
          >
            Tentar novamente
          </button>
          <Link
            href="/app"
            className="rounded-md border border-slate-300 px-4 py-2 font-semibold text-slate-700 hover:bg-slate-50"
          >
            Voltar à área protegida
          </Link>
        </div>
      </section>
    </main>
  );
}
