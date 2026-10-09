import Link from 'next/link';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { formatCnj } from '@/lib/processes/cnj';
import { createProcessAction } from './actions';
import { RefreshProcessButton } from './refresh-process-button';
import { DeactivateProcessButton } from './deactivate-process-button';
import { ProcessesSpreadsheetScroll } from './processes-spreadsheet-scroll';
import { ProcessExportControls } from './process-export-controls';
import { buildProcessExportRow } from './processes-export-model';
import { RefreshClientPortfolioButton } from '../clientes/refresh-client-portfolio-button';
import { getClientPortfolioReadModels } from '@/lib/clients/portfolio';
import { parsePortfolioGridFilters } from './portfolio-grid-filters';
import {
  PORTFOLIO_SPREADSHEET_COLUMNS,
  formatNewsCount,
  formatSpreadsheetDate,
  formatSpreadsheetDateOnly,
  getMonitoringStateLabel,
  isPortfolioColumnVisibleByDefault,
} from './processes-spreadsheet-model';

function visibilityLabel(isPublic: boolean) {
  return isPublic ? 'Público' : 'Sigiloso';
}

function statusLabel(status: string) {
  return status === 'active' ? 'Ativo' : 'Inativo';
}

export default async function ProcessesPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { profile } = await requirePermission('view_operational_data');
  const canMutate = profile.role === 'lawyer' || profile.role === 'operator';
  const canManageMonitoring =
    profile.role === 'lawyer' || profile.role === 'operator';
  const supabase = await createClient();
  const params = searchParams ? await searchParams : {};
  const gridFilters = parsePortfolioGridFilters(params);
  const selectedClientId = gridFilters.clientId;
  const { clientId: _clientId, ...readModelFilters } = gridFilters;
  void _clientId;
  const addProcessOpen =
    (Array.isArray(params.add) ? params.add[0] : params.add) === '1';
  const processQuery = supabase
    .from('legal_process')
    .select(
      'id,client_id,cnj_number,tribunal,system,is_public,status,created_at'
    )
    .order('created_at', { ascending: false });
  if (selectedClientId) processQuery.eq('client_id', selectedClientId);
  if (typeof gridFilters.isPublic === 'boolean') {
    processQuery.eq('is_public', gridFilters.isPublic);
  }
  const [
    { data: clients, error: clientsError },
    { data: parties, error: partiesError },
    { data: processes, error: processesError },
  ] = await Promise.all([
    supabase
      .from('client')
      .select('id,party_id,status')
      .eq('status', 'active')
      .order('created_at', { ascending: false }),
    supabase
      .from('party')
      .select('id,display_name,party_type,status')
      .eq('status', 'active')
      .order('display_name'),
    processQuery,
  ]);
  const portfolios = await getClientPortfolioReadModels(
    supabase,
    selectedClientId,
    readModelFilters
  );
  if (clientsError || partiesError || processesError)
    throw new Error('Não foi possível carregar os dados de processos.');

  const partyById = new Map((parties ?? []).map((party) => [party.id, party]));
  const clientById = new Map(
    (clients ?? []).map((client) => [client.id, client])
  );
  const portfolioProcessById = new Map(
    portfolios.flatMap((portfolio) =>
      portfolio.processes.map(
        (process) => [process.processId, process] as const
      )
    )
  );
  const portfolioProcesses = [...portfolioProcessById.values()];
  const hasReadModelFilters = Object.keys(readModelFilters).length > 0;
  const visibleProcesses = hasReadModelFilters
    ? (processes ?? []).filter((process) =>
        portfolioProcessById.has(process.id)
      )
    : (processes ?? []);
  const portfolioSummary = {
    total: visibleProcesses.length,
    novelty: portfolioProcesses.filter((process) => process.hasNews).length,
    notConsulted: portfolioProcesses.filter(
      (process) => process.state === 'not_consulted'
    ).length,
    failure: portfolioProcesses.filter((process) => process.state === 'failure')
      .length,
    review: portfolioProcesses.filter(
      (process) => process.state === 'manual_review'
    ).length,
    updating: portfolioProcesses.filter(
      (process) => process.state === 'updating'
    ).length,
  };
  const selectedClientName = selectedClientId
    ? partyById.get(
        clients?.find((client) => client.id === selectedClientId)?.party_id ??
          ''
      )?.display_name
    : null;
  const exportRows = visibleProcesses.map((process, index) => {
    const client = clientById.get(process.client_id);
    const principal = client ? partyById.get(client.party_id) : undefined;
    return buildProcessExportRow({
      process,
      index,
      clientName: principal?.display_name ?? 'Cliente não encontrado',
      portfolioProcess: portfolioProcessById.get(process.id),
    });
  });

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl flex-wrap items-center justify-between gap-2 px-4 py-2">
          <div className="flex flex-wrap items-center gap-4">
            <Link href="/app" className="group">
              <span className="font-semibold text-slate-950 group-hover:text-sky-700">
                Juridico
              </span>
              <p className="text-xs text-slate-500">Início</p>
            </Link>
            <div className="flex items-center gap-4 text-sm font-medium">
              <Link
                className="font-semibold text-sky-700"
                href="/app/processos"
              >
                Processos
              </Link>
              <Link
                className="text-slate-700 hover:text-sky-700"
                href="/app/clientes"
              >
                Clientes
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
          <Link
            href="/app"
            className="text-sm font-semibold text-sky-700 hover:underline"
          >
            Voltar ao Início
          </Link>
        </div>
      </nav>

      <div className="mx-auto max-w-7xl space-y-6 px-4 py-8 sm:px-6 lg:px-8">
        <header className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold text-slate-950">
              {selectedClientName
                ? `Processos de ${selectedClientName}`
                : 'Processos'}
            </h1>
            <p className="mt-1 text-sm text-slate-600">
              Consulte e compare os processos da carteira em uma única grade.
            </p>
          </div>
          {canMutate ? (
            <div className="flex flex-wrap items-center gap-2">
              <Link
                href={`/app/processos?${selectedClientId ? `clientId=${selectedClientId}&` : ''}add=1`}
                className="rounded-md bg-sky-700 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-800"
              >
                Adicionar processo
              </Link>
              <Link
                href="/app/processos/importar"
                className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-700 hover:border-sky-500 hover:text-sky-700"
              >
                Importar carteira
              </Link>
            </div>
          ) : null}
        </header>

        {canMutate ? (
          <details
            data-testid="process-create-panel"
            open={addProcessOpen}
            className="rounded-xl border border-slate-200 bg-white shadow-sm"
          >
            <summary className="cursor-pointer list-none px-5 py-4 text-sm font-semibold text-slate-800 focus:outline-none focus:ring-2 focus:ring-sky-500">
              Adicionar processo manualmente
            </summary>
            <form
              data-testid="process-create-form"
              action={async (formData) => {
                'use server';
                await createProcessAction(formData);
              }}
              className="border-t border-slate-200 p-5"
            >
              <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-5">
                <label className="block text-sm font-medium text-slate-700">
                  Cliente
                  <select
                    name="clientId"
                    required
                    defaultValue={selectedClientId ?? ''}
                    className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
                  >
                    <option value="">Selecione o cliente</option>
                    {(clients ?? []).map((client) => {
                      const principal = partyById.get(client.party_id);
                      return (
                        <option key={client.id} value={client.id}>
                          {principal?.display_name ?? 'Cliente'}
                        </option>
                      );
                    })}
                  </select>
                </label>
                <label className="block text-sm font-medium text-slate-700">
                  Número CNJ
                  <input
                    name="cnj"
                    required
                    placeholder="0004453-12.2026.8.16.0000"
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  />
                </label>
                <label className="block text-sm font-medium text-slate-700">
                  Tribunal
                  <input
                    name="tribunal"
                    required
                    maxLength={200}
                    placeholder="Tribunal de Justiça"
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  />
                </label>
                <label className="block text-sm font-medium text-slate-700">
                  Sistema
                  <input
                    name="system"
                    maxLength={120}
                    placeholder="PJe"
                    className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                  />
                </label>
                <label className="block text-sm font-medium text-slate-700">
                  Publicidade
                  <select
                    name="isPublic"
                    defaultValue="public"
                    className="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2"
                  >
                    <option value="public">Público</option>
                    <option value="private">Sigiloso</option>
                  </select>
                </label>
                <div className="flex items-end">
                  <button
                    className="w-full rounded-md bg-sky-700 px-4 py-2 font-semibold text-white hover:bg-sky-800"
                    type="submit"
                  >
                    Cadastrar processo
                  </button>
                </div>
              </div>
            </form>
          </details>
        ) : null}

        <section className="overflow-hidden rounded-lg border border-slate-300 bg-white shadow-sm">
          <div className="border-b-2 border-slate-300 p-5 sm:p-6">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div>
                <h2 className="text-lg font-semibold text-slate-950">
                  Carteira de processos
                </h2>
                <p className="mt-1 text-sm text-slate-600">
                  Uma linha por processo, com uma informação em cada coluna.
                </p>
              </div>
              <div className="flex flex-wrap items-end gap-3">
                <p className="text-xs font-medium tabular-nums text-slate-600">
                  Exibindo {portfolioSummary.total} processo(s)
                </p>
                {canManageMonitoring && selectedClientId ? (
                  <RefreshClientPortfolioButton
                    clientId={selectedClientId}
                    buttonLabel="Atualizar todos"
                  />
                ) : null}
              </div>
            </div>
            <form
              data-testid="client-portfolio-filter"
              method="get"
              className="grid w-full gap-3 border-t border-slate-200 pt-4 md:grid-cols-[minmax(18rem,2fr)_minmax(12rem,1fr)_minmax(11rem,1fr)_minmax(10rem,1fr)_auto_auto]"
            >
              <label className="text-xs font-semibold uppercase tracking-wide text-slate-600">
                Buscar processo ou cliente
                <input
                  name="q"
                  defaultValue={gridFilters.search ?? ''}
                  placeholder="CNJ, nome, tribunal ou andamento"
                  className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-slate-800"
                />
              </label>
              <label className="text-xs font-semibold uppercase tracking-wide text-slate-600">
                Cliente
                <select
                  name="clientId"
                  defaultValue={selectedClientId ?? ''}
                  className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-slate-800"
                >
                  <option value="">Todos os clientes</option>
                  {(clients ?? []).map((client) => (
                    <option key={client.id} value={client.id}>
                      {partyById.get(client.party_id)?.display_name ??
                        'Cliente sem nome'}
                    </option>
                  ))}
                </select>
              </label>
              <label className="text-xs font-semibold uppercase tracking-wide text-slate-600">
                Estado da consulta
                <select
                  name="state"
                  defaultValue={gridFilters.state ?? ''}
                  className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-slate-800"
                >
                  <option value="">Todos</option>
                  <option value="not_consulted">Não consultado</option>
                  <option value="updating">Atualizando</option>
                  <option value="first_observation">Primeira consulta</option>
                  <option value="unchanged">Sem novidade</option>
                  <option value="changed">Com novidades</option>
                  <option value="failure">Falha</option>
                  <option value="manual_review">Revisão necessária</option>
                </select>
              </label>
              <label className="text-xs font-semibold uppercase tracking-wide text-slate-600">
                Visibilidade
                <select
                  name="visibility"
                  defaultValue={
                    typeof gridFilters.isPublic === 'boolean'
                      ? gridFilters.isPublic
                        ? 'public'
                        : 'private'
                      : ''
                  }
                  className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-slate-800"
                >
                  <option value="">Todos</option>
                  <option value="public">Público</option>
                  <option value="private">Sigiloso</option>
                </select>
              </label>
              <button
                type="submit"
                className="self-end rounded-md bg-sky-700 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-800"
              >
                Buscar
              </button>
              <Link
                href="/app/processos"
                className="self-end rounded-md border border-slate-300 bg-white px-4 py-2 text-center text-sm font-semibold text-slate-700 hover:border-sky-500 hover:text-sky-700"
              >
                Limpar
              </Link>
            </form>
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-300 bg-white px-4 py-2.5 text-xs text-slate-600">
            <p className="font-semibold text-slate-700">Grade da carteira</p>
            <p>Use as barras de rolagem para comparar as colunas.</p>
          </div>

          <ProcessExportControls
            rows={exportRows}
            columns={PORTFOLIO_SPREADSHEET_COLUMNS}
          />

          <ProcessesSpreadsheetScroll>
            <table
              data-testid="processes-spreadsheet"
              className="w-max min-w-[2600px] table-fixed border-separate border-spacing-0 text-left text-xs text-slate-700"
            >
              <caption className="sr-only">
                Carteira de processos organizada em colunas comparáveis
              </caption>
              <colgroup>
                {PORTFOLIO_SPREADSHEET_COLUMNS.map((column) => (
                  <col
                    key={column.key}
                    data-portfolio-column={column.key}
                    hidden={!isPortfolioColumnVisibleByDefault(column.key)}
                    className={column.width}
                  />
                ))}
              </colgroup>
              <thead className="sticky top-0 z-20 bg-slate-100 text-slate-700">
                <tr>
                  {PORTFOLIO_SPREADSHEET_COLUMNS.map((column) => (
                    <th
                      key={column.key}
                      scope="col"
                      data-portfolio-column={column.key}
                      hidden={!isPortfolioColumnVisibleByDefault(column.key)}
                      className="border-b-2 border-r border-slate-300 px-3 py-3 text-[10px] font-bold uppercase tracking-[0.08em] last:border-r-0"
                    >
                      {column.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {visibleProcesses.length === 0 ? (
                  <tr>
                    <td
                      colSpan={PORTFOLIO_SPREADSHEET_COLUMNS.length}
                      className="px-4 py-10 text-center text-sm text-slate-500"
                    >
                      Nenhum processo cadastrado.
                    </td>
                  </tr>
                ) : null}
                {visibleProcesses.map((process) => {
                  const client = clientById.get(process.client_id);
                  const principal = client
                    ? partyById.get(client.party_id)
                    : undefined;
                  const portfolioProcess = portfolioProcessById.get(process.id);
                  const monitoringState =
                    portfolioProcess?.monitoringState ?? 'not_consulted';
                  const movement = portfolioProcess?.lastMovement;

                  return (
                    <tr
                      key={process.id}
                      data-process-row={process.id}
                      data-process-id={process.id}
                      data-process-cnj={process.cnj_number}
                      className="align-top odd:bg-white even:bg-slate-50/70 hover:bg-sky-50"
                    >
                      <td
                        data-portfolio-column="select"
                        className="border-b border-r border-slate-200 px-2 py-3 text-center font-mono text-[11px] tabular-nums text-slate-500"
                      >
                        <input
                          type="checkbox"
                          data-process-selection={process.cnj_number}
                          data-process-id={process.id}
                          aria-label={`Selecionar processo ${formatCnj(process.cnj_number)}`}
                          className="h-4 w-4 rounded border-slate-300 text-sky-700 focus:ring-sky-600"
                        />
                      </td>
                      <td
                        data-portfolio-column="process"
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        <Link
                          href={`/app/processos/historico?cnj=${encodeURIComponent(process.cnj_number)}`}
                          aria-label={`Abrir histórico do processo ${formatCnj(process.cnj_number)}`}
                          className="font-mono text-[13px] font-semibold tabular-nums text-sky-800 underline decoration-sky-300 underline-offset-2 hover:text-sky-950"
                        >
                          {formatCnj(process.cnj_number)}
                        </Link>
                      </td>
                      <td
                        data-portfolio-column="client"
                        className="border-b border-r border-slate-200 px-3 py-3 font-medium text-slate-900"
                      >
                        {principal?.display_name ?? 'Cliente não encontrado'}
                      </td>
                      <td
                        data-portfolio-column="registrationStatus"
                        className="border-b border-r border-slate-200 px-3 py-3 font-semibold text-slate-900"
                      >
                        {statusLabel(process.status)}
                      </td>
                      <td
                        data-portfolio-column="visibility"
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {visibilityLabel(process.is_public)}
                      </td>
                      <td
                        data-portfolio-column="monitoringState"
                        className="border-b border-r border-slate-200 px-3 py-3 font-semibold text-slate-900"
                      >
                        {getMonitoringStateLabel(monitoringState)}
                      </td>
                      <td
                        data-portfolio-column="tribunal"
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {process.tribunal}
                      </td>
                      <td
                        data-portfolio-column="system"
                        hidden={!isPortfolioColumnVisibleByDefault('system')}
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {process.system ??
                          portfolioProcess?.system ??
                          'Não informado'}
                      </td>
                      <td
                        data-portfolio-column="processClass"
                        hidden={
                          !isPortfolioColumnVisibleByDefault('processClass')
                        }
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {portfolioProcess?.processClass ??
                          'Ainda não informada'}
                      </td>
                      <td
                        data-portfolio-column="degree"
                        hidden={!isPortfolioColumnVisibleByDefault('degree')}
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {portfolioProcess?.degree ?? 'Ainda não informado'}
                      </td>
                      <td
                        data-portfolio-column="court"
                        hidden={!isPortfolioColumnVisibleByDefault('court')}
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {portfolioProcess?.court ?? 'Não informado'}
                      </td>
                      <td
                        data-portfolio-column="sourceStatus"
                        hidden={
                          !isPortfolioColumnVisibleByDefault('sourceStatus')
                        }
                        className="border-b border-r border-slate-200 px-3 py-3 leading-4 text-slate-600"
                      >
                        {portfolioProcess?.sourceStatus ??
                          'Não informado pela fonte'}
                      </td>
                      <td
                        data-portfolio-column="movementCode"
                        hidden={
                          !isPortfolioColumnVisibleByDefault('movementCode')
                        }
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {movement?.code ?? 'Não informado'}
                      </td>
                      <td
                        data-portfolio-column="movementType"
                        className="border-b border-r border-slate-200 px-3 py-3 font-medium text-slate-900"
                      >
                        {movement?.type ?? 'Não informado'}
                      </td>
                      <td
                        data-portfolio-column="movementDate"
                        className="whitespace-nowrap border-b border-r border-slate-200 px-3 py-3"
                      >
                        {formatSpreadsheetDateOnly(
                          movement?.date ?? null,
                          'Não informado'
                        )}
                      </td>
                      <td
                        data-portfolio-column="description"
                        className="max-w-[340px] whitespace-normal break-words border-b border-r border-slate-200 px-3 py-3 leading-4"
                      >
                        {movement?.description ??
                          'Nenhum detalhe de andamento informado'}
                      </td>
                      <td
                        data-portfolio-column="movementCourt"
                        hidden={
                          !isPortfolioColumnVisibleByDefault('movementCourt')
                        }
                        className="border-b border-r border-slate-200 px-3 py-3"
                      >
                        {movement?.court ?? 'Não informado'}
                      </td>
                      <td
                        data-portfolio-column="lastConsulted"
                        className="whitespace-nowrap border-b border-r border-slate-200 px-3 py-3"
                      >
                        {formatSpreadsheetDate(
                          portfolioProcess?.lastConsultedAt ?? null,
                          'Não consultado'
                        )}
                      </td>
                      <td
                        data-portfolio-column="sourceUpdated"
                        className="whitespace-nowrap border-b border-r border-slate-200 px-3 py-3"
                      >
                        {formatSpreadsheetDate(
                          portfolioProcess?.sourceUpdatedAt ?? null,
                          'Não informado'
                        )}
                      </td>
                      <td
                        data-portfolio-column="newMovements"
                        className="border-b border-r border-slate-200 px-3 py-3 font-semibold"
                      >
                        {formatNewsCount(
                          portfolioProcess?.newMovementCount ?? 0,
                          portfolioProcess?.hasNews ?? false,
                          monitoringState
                        )}
                      </td>
                      <td
                        data-portfolio-column="actions"
                        className="border-b border-slate-200 px-3 py-3"
                      >
                        <div className="flex min-w-[190px] flex-wrap items-center gap-2">
                          {canManageMonitoring &&
                          process.status === 'active' ? (
                            process.is_public ? (
                              <RefreshProcessButton
                                processId={process.id}
                                compact
                              />
                            ) : (
                              <span className="text-xs text-slate-600">
                                Consulta indisponível para processo sigiloso.
                              </span>
                            )
                          ) : null}
                          {canMutate && process.status === 'active' ? (
                            <DeactivateProcessButton
                              processId={process.id}
                              compact
                            />
                          ) : null}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </ProcessesSpreadsheetScroll>
        </section>
      </div>
    </main>
  );
}
