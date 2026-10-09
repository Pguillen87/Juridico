import Link from 'next/link';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { formatCnj, normalizeCnj } from '@/lib/processes/cnj';
import {
  getClientPortfolioProcessDetail,
  type ClientPortfolioProcessDetail,
} from '@/lib/clients/portfolio';

function queryValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function formatDate(value: string | null) {
  return value ? new Date(value).toLocaleString('pt-BR') : 'Não informado';
}

function processStateLabel(state: ClientPortfolioProcessDetail['state']) {
  switch (state) {
    case 'not_consulted':
      return 'Ainda não consultado';
    case 'updating':
      return 'Atualizando';
    case 'first_observation':
      return 'Primeira consulta';
    case 'unchanged':
      return 'Sem novidade';
    case 'changed':
      return 'Com novidades';
    case 'failure':
      return 'Falha na consulta';
    case 'manual_review':
      return 'Revisão necessária';
  }
}

async function loadProcessDetail(cnjInput: string | undefined) {
  if (!cnjInput) return null;

  let normalizedCnj: string;
  try {
    normalizedCnj = normalizeCnj(cnjInput);
  } catch {
    return null;
  }

  const supabase = await createClient();
  const { data: process, error } = await supabase
    .from('legal_process')
    .select('id')
    .eq('cnj_number', normalizedCnj)
    .maybeSingle();
  if (error || !process) return null;

  return getClientPortfolioProcessDetail(supabase, process.id);
}

function ProcessHistoryTable({
  detail,
}: {
  readonly detail: ClientPortfolioProcessDetail;
}) {
  if (detail.movements.length === 0) {
    return (
      <p className="rounded-lg border border-dashed border-slate-300 bg-slate-50 px-4 py-8 text-sm text-slate-600">
        Nenhuma movimentação disponível para este processo.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto rounded-lg border border-slate-300">
      <table className="min-w-[900px] w-full text-left text-sm">
        <caption className="sr-only">
          Histórico de movimentações do processo
        </caption>
        <thead className="bg-slate-100 text-xs uppercase tracking-wide text-slate-600">
          <tr>
            <th scope="col" className="border-b border-slate-300 px-3 py-3">
              Data
            </th>
            <th scope="col" className="border-b border-slate-300 px-3 py-3">
              Tipo do andamento
            </th>
            <th scope="col" className="border-b border-slate-300 px-3 py-3">
              Descrição
            </th>
            <th scope="col" className="border-b border-slate-300 px-3 py-3">
              Órgão julgador
            </th>
            <th scope="col" className="border-b border-slate-300 px-3 py-3">
              Código
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-200">
          {detail.movements.map((movement, index) => (
            <tr key={`${movement.date}-${movement.code}-${index}`}>
              <td className="whitespace-nowrap px-3 py-3 align-top">
                {formatDate(movement.date)}
              </td>
              <td className="px-3 py-3 align-top font-medium text-slate-900">
                {movement.type ?? 'Não informado'}
              </td>
              <td className="min-w-[360px] px-3 py-3 align-top">
                {movement.description ?? 'Não informado'}
              </td>
              <td className="min-w-[220px] px-3 py-3 align-top">
                {movement.court ?? 'Não informado'}
              </td>
              <td className="px-3 py-3 align-top font-mono text-xs">
                {movement.code ?? 'Não informado'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default async function ProcessHistoryPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requirePermission('view_operational_data');
  const params = searchParams ? await searchParams : {};
  const rawCnj = queryValue(params.cnj);
  const detail = await loadProcessDetail(rawCnj);
  const formattedCnj = rawCnj
    ? (() => {
        try {
          return formatCnj(rawCnj);
        } catch {
          return rawCnj;
        }
      })()
    : null;

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between gap-4 px-4 py-2 sm:px-6 lg:px-8">
          <div>
            <Link
              href="/app/processos"
              className="font-semibold text-slate-950 hover:text-sky-700"
            >
              Processos
            </Link>
            <p className="text-xs text-slate-500">Histórico do processo</p>
          </div>
          <Link
            href="/app/processos"
            className="text-sm font-semibold text-sky-700 hover:underline"
          >
            Voltar para a carteira
          </Link>
        </div>
      </nav>

      <div className="mx-auto max-w-7xl space-y-6 px-4 py-8 sm:px-6 lg:px-8">
        <header>
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-sky-700">
            Consulta processual
          </p>
          <h1 className="mt-2 text-3xl font-bold text-slate-950">
            Histórico do processo
          </h1>
          <p className="mt-1 text-sm text-slate-600">
            Consulte os dados informados pela fonte e todas as movimentações em
            uma tabela separada da carteira.
          </p>
        </header>

        {!detail ? (
          <section className="rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-950">
            {formattedCnj
              ? `Não encontramos o processo ${formattedCnj} na carteira deste escritório.`
              : 'Informe um processo válido para consultar o histórico.'}
          </section>
        ) : (
          <>
            <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    Processo
                  </p>
                  <p className="mt-1 font-mono text-sm font-semibold text-slate-950">
                    {formatCnj(detail.cnjNumber)}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    Tribunal
                  </p>
                  <p className="mt-1 text-sm text-slate-800">
                    {detail.tribunal}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    Estado da consulta
                  </p>
                  <p className="mt-1 text-sm font-semibold text-slate-900">
                    {processStateLabel(detail.state)}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    Última consulta
                  </p>
                  <p className="mt-1 text-sm text-slate-800">
                    {formatDate(detail.lastConsultedAt)}
                  </p>
                </div>
              </div>
            </section>

            <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
                <div>
                  <h2 className="text-lg font-semibold text-slate-950">
                    Movimentações
                  </h2>
                  <p className="mt-1 text-sm text-slate-600">
                    Cada informação ocupa sua própria coluna para facilitar a
                    leitura e a comparação.
                  </p>
                </div>
                <p className="text-sm text-slate-600">
                  {detail.movements.length} movimentação(ões)
                </p>
              </div>
              <ProcessHistoryTable detail={detail} />
            </section>
          </>
        )}
      </div>
    </main>
  );
}
