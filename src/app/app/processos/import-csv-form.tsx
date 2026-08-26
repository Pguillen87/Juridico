'use client';

import { useState } from 'react';
import { confirmImportAction, previewImportAction } from './actions';

type PreviewState = {
  error?: string;
  success?: boolean;
  preview?: {
    preview_id: string;
    expires_at: string;
    summary: Record<string, unknown>;
  } | null;
  rows?: Array<Record<string, unknown>>;
  errors?: Array<{ line: number; message: string }>;
  warnings?: Array<{ line: number; message: string }>;
  summary?: Record<string, unknown>;
};

export function ImportCsvForm() {
  const [state, setState] = useState<PreviewState | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
      <h2 className="text-lg font-semibold text-slate-950">
        Importar carteira CSV
      </h2>
      <p className="mt-1 text-sm text-slate-600">
        O arquivo será analisado sem persistir processos. Somente a confirmação
        do preview cria registros.
      </p>
      <form
        className="mt-5 space-y-4"
        action={async (formData) => {
          setBusy(true);
          setState(await previewImportAction(formData));
          setBusy(false);
        }}
      >
        <label className="block text-sm font-medium text-slate-700">
          Arquivo CSV
          <input
            name="file"
            type="file"
            accept=".csv,text/csv"
            required
            className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
        </label>
        <p className="text-xs text-slate-500">
          Cabeçalho: cnj, cliente, tribunal, sistema, parte, papel, publicidade,
          monitoramento, observacoes. Limite: 2 MB e 1000 linhas.
        </p>
        <button
          disabled={busy}
          className="rounded-md bg-slate-900 px-4 py-2 font-semibold text-white disabled:opacity-50"
          type="submit"
        >
          {busy ? 'Gerando prévia…' : 'Gerar prévia'}
        </button>
      </form>

      {state?.error ? (
        <div className="mt-5 rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
          {state.error}
        </div>
      ) : null}
      {state?.errors?.length ? (
        <div className="mt-4 rounded-md border border-rose-200 bg-rose-50 p-4 text-sm text-rose-900">
          <p className="font-semibold">Erros por linha</p>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            {state.errors.map((error, index) => (
              <li key={`${error.line}-${index}`}>
                Linha {error.line}: {error.message}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      {state?.warnings?.length ? (
        <div className="mt-4 rounded-md border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          <p className="font-semibold">Avisos</p>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            {state.warnings.map((warning, index) => (
              <li key={`${warning.line}-${index}`}>
                Linha {warning.line}: {warning.message}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      {state?.rows?.length ? (
        <div className="mt-5 overflow-x-auto rounded-lg border border-slate-200">
          <table className="min-w-full text-left text-xs">
            <thead className="bg-slate-50 text-slate-600">
              <tr>
                <th className="px-3 py-2">Linha</th>
                <th className="px-3 py-2">CNJ</th>
                <th className="px-3 py-2">Cliente</th>
                <th className="px-3 py-2">Parte</th>
                <th className="px-3 py-2">Papel</th>
                <th className="px-3 py-2">Monitoramento</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {state.rows.map((row, index) => (
                <tr key={`${String(row.line ?? index)}-${index}`}>
                  <td className="px-3 py-2">{String(row.line ?? index + 1)}</td>
                  <td className="px-3 py-2 font-mono">
                    {String(row.cnj ?? '')}
                  </td>
                  <td className="px-3 py-2">{String(row.clientName ?? '')}</td>
                  <td className="px-3 py-2">{String(row.partyName ?? '—')}</td>
                  <td className="px-3 py-2">{String(row.role ?? '—')}</td>
                  <td className="px-3 py-2">
                    {String(row.monitoringStatus ?? 'paused')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
      {state?.preview ? (
        <div className="mt-5 rounded-lg border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-950">
          <p className="font-semibold">
            Prévia pronta: {state.preview.preview_id.slice(0, 8)}
          </p>
          <p className="mt-1">
            Expira em{' '}
            {new Date(state.preview.expires_at).toLocaleString('pt-BR')} ·{' '}
            {String(state.preview.summary.total_rows ?? 0)} linha(s) válida(s).
          </p>
          <form
            className="mt-4"
            action={async (formData) => {
              setBusy(true);
              setState(await confirmImportAction(formData));
              setBusy(false);
            }}
          >
            <input
              type="hidden"
              name="previewId"
              value={state.preview.preview_id}
            />
            <button
              disabled={busy}
              className="rounded-md bg-emerald-700 px-4 py-2 font-semibold text-white disabled:opacity-50"
              type="submit"
            >
              {busy ? 'Confirmando…' : 'Confirmar importação'}
            </button>
          </form>
        </div>
      ) : null}
      {state?.summary ? (
        <div className="mt-4 rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900">
          Importação concluída: {String(state.summary.processes_created ?? 0)}{' '}
          processo(s) e {String(state.summary.relations_created ?? 0)}{' '}
          vínculo(s).
        </div>
      ) : null}
    </section>
  );
}
