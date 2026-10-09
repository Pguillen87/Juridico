'use client';

import { useState } from 'react';
import {
  getClientPortfolioProcessDetailAction,
  type PortfolioProcessDetailActionResult,
} from '../processos/actions';
import type { ClientPortfolioProcess } from '@/lib/clients/portfolio';

function formatDate(value: string | null) {
  return value ? new Date(value).toLocaleString('pt-BR') : 'Não informado';
}

export function ProcessPortfolioDetails({
  process,
}: {
  readonly process: ClientPortfolioProcess;
}) {
  const [state, setState] = useState<PortfolioProcessDetailActionResult | null>(
    null
  );
  const [pending, setPending] = useState(false);

  async function loadDetails() {
    if (state || pending) return;
    setPending(true);
    try {
      setState(await getClientPortfolioProcessDetailAction(process.processId));
    } finally {
      setPending(false);
    }
  }

  return (
    <details onToggle={(event) => event.currentTarget.open && loadDetails()}>
      <summary className="cursor-pointer text-xs font-semibold text-sky-800 hover:text-sky-950">
        Ver detalhes e movimentações
      </summary>
      <div className="mt-3 border-t border-slate-200 pt-3 text-xs text-slate-700">
        {pending ? <p>Carregando detalhes…</p> : null}
        {state && !state.success ? (
          <p className="text-rose-800" role="alert">
            {state.message}
          </p>
        ) : null}
        {state && state.success && state.detail ? (
          <div className="space-y-4">
            <dl className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <dt className="font-semibold text-slate-500">Ajuizamento</dt>
                <dd>{formatDate(state.detail.filingDate)}</dd>
              </div>
              <div>
                <dt className="font-semibold text-slate-500">Sistema</dt>
                <dd>{state.detail.system ?? 'Não informado'}</dd>
              </div>
              <div>
                <dt className="font-semibold text-slate-500">
                  Sigilo da fonte
                </dt>
                <dd>{state.detail.secrecyLevel ?? 'Não informado'}</dd>
              </div>
              <div>
                <dt className="font-semibold text-slate-500">Assuntos</dt>
                <dd>
                  {state.detail.subjects.length
                    ? state.detail.subjects.join(', ')
                    : 'Não informados'}
                </dd>
              </div>
            </dl>
            <div>
              <h4 className="font-semibold text-slate-900">
                Partes vinculadas
              </h4>
              {state.detail.parties.length ? (
                <ul className="mt-1 list-inside list-disc">
                  {state.detail.parties.map((party, index) => (
                    <li key={`${party.name}-${party.role}-${index}`}>
                      {party.name} · {party.role}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="mt-1">Nenhuma parte vinculada manualmente.</p>
              )}
            </div>
            <div>
              <h4 className="font-semibold text-slate-900">
                Histórico de movimentações
              </h4>
              {state.detail.movements.length ? (
                <div className="mt-2 overflow-x-auto rounded border border-slate-200">
                  <table className="min-w-full text-left">
                    <thead className="bg-slate-50 text-slate-600">
                      <tr>
                        <th className="px-3 py-2">Data</th>
                        <th className="px-3 py-2">Tipo</th>
                        <th className="px-3 py-2">Descrição</th>
                        <th className="px-3 py-2">Órgão julgador</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-200">
                      {state.detail.movements.map((movement, index) => (
                        <tr key={`${movement.date}-${movement.code}-${index}`}>
                          <td className="whitespace-nowrap px-3 py-2">
                            {formatDate(movement.date)}
                          </td>
                          <td className="px-3 py-2">
                            {movement.type ?? movement.code ?? 'Não informado'}
                          </td>
                          <td className="min-w-64 px-3 py-2">
                            {movement.description ?? 'Não informado'}
                          </td>
                          <td className="px-3 py-2">
                            {movement.court ?? 'Não informado'}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <p className="mt-1">Nenhuma movimentação disponível.</p>
              )}
            </div>
          </div>
        ) : null}
      </div>
    </details>
  );
}
