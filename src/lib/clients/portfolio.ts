import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/types/database.types';

export const CLIENT_PORTFOLIO_STATES = [
  'not_consulted',
  'updating',
  'first_observation',
  'unchanged',
  'changed',
  'failure',
  'manual_review',
] as const;

export type ClientPortfolioProcessState =
  (typeof CLIENT_PORTFOLIO_STATES)[number];

export type ClientPortfolioMovement = {
  date: string | null;
  code: string | null;
  type: string | null;
  description: string | null;
  court: string | null;
};

export type ClientPortfolioProcess = {
  processId: string;
  cnjNumber: string;
  tribunal: string;
  isPublic: boolean;
  officeStatus: 'active' | 'inactive';
  sourceStatus: string | null;
  monitoringState: ClientPortfolioProcessState;
  processClass: string | null;
  degree: string | null;
  court: string | null;
  filingDate: string | null;
  secrecyLevel: string | null;
  system: string | null;
  lastConsultedAt: string | null;
  sourceUpdatedAt: string | null;
  lastMovement: ClientPortfolioMovement | null;
  hasNews: boolean;
  newMovementCount: number;
  responsibleName: string | null;
  nextAction: string | null;
  /** Compatibilidade de leitura com componentes da primeira carteira. */
  status: 'active' | 'inactive';
  state: ClientPortfolioProcessState;
  recentMovement: ClientPortfolioMovement | null;
};

export type ClientPortfolioProcessDetail = ClientPortfolioProcess & {
  subjects: string[];
  parties: Array<{ name: string; role: string }>;
  movements: ClientPortfolioMovement[];
};

export type ClientPortfolioReadModel = {
  clientId: string;
  clientName: string;
  processCount: number;
  noveltyCount: number;
  notUpdatedCount: number;
  failureCount: number;
  reviewCount: number;
  lastConsultedAt: string | null;
  lastSourceUpdatedAt: string | null;
  processes: ClientPortfolioProcess[];
};

export type ClientPortfolioRefreshProgress = {
  state: 'queued' | 'running' | 'completed' | 'completed_with_issues';
  totalCount: number;
  eligibleCount: number;
  skippedCount: number;
  pendingCount: number;
  runningCount: number;
  completedCount: number;
  noveltyCount: number;
  unchangedCount: number;
  failureCount: number;
  reviewCount: number;
  lastUpdatedAt: string | null;
};

export type ClientPortfolioGridFilters = {
  clientId?: string;
  search?: string;
  state?: ClientPortfolioProcessState;
  isPublic?: boolean;
};

type PortfolioDatabaseClient = SupabaseClient<Database>;

function record(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`Resposta inválida para ${label}.`);
  }
  return value as Record<string, unknown>;
}

function requiredString(value: unknown, label: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`Resposta inválida para ${label}.`);
  }
  return value;
}

function nullableString(value: unknown, label: string): string | null {
  if (value === null || value === undefined) return null;
  return requiredString(value, label);
}

function nonNegativeInteger(value: unknown, label: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
    throw new Error(`Resposta inválida para ${label}.`);
  }
  return value;
}

function processState(value: unknown): ClientPortfolioProcessState {
  if (
    typeof value !== 'string' ||
    !(CLIENT_PORTFOLIO_STATES as readonly string[]).includes(value)
  ) {
    throw new Error('Resposta inválida para estado de processo.');
  }
  return value as ClientPortfolioProcessState;
}

function officeStatus(value: unknown): 'active' | 'inactive' {
  if (value !== 'active' && value !== 'inactive') {
    throw new Error('Resposta inválida para situação do cadastro.');
  }
  return value;
}

function parseMovement(value: unknown, label: string): ClientPortfolioMovement {
  const movement = record(value, label);
  return {
    date: nullableString(movement.date, `${label}: data`),
    code: nullableString(movement.code, `${label}: código`),
    type: nullableString(movement.type, `${label}: tipo`),
    description: nullableString(movement.description, `${label}: descrição`),
    court: nullableString(movement.court, `${label}: órgão julgador`),
  };
}

function parseNullableMovement(
  value: unknown,
  label: string
): ClientPortfolioMovement | null {
  if (value === null || value === undefined) return null;
  return parseMovement(value, label);
}

function parseProcess(value: unknown): ClientPortfolioProcess {
  const process = record(value, 'processo da carteira');
  const state = processState(process.monitoringState ?? process.state);
  const registeredStatus = officeStatus(process.officeStatus ?? process.status);
  const lastMovement = parseNullableMovement(
    process.lastMovement ?? process.recentMovement,
    'último andamento'
  );
  return {
    processId: requiredString(process.processId, 'processo da carteira'),
    cnjNumber: requiredString(process.cnjNumber, 'CNJ do processo'),
    tribunal: requiredString(process.tribunal, 'tribunal do processo'),
    isPublic: process.isPublic === true,
    officeStatus: registeredStatus,
    sourceStatus: nullableString(
      process.sourceStatus,
      'situação informada pela fonte'
    ),
    monitoringState: state,
    processClass: nullableString(process.processClass, 'classe processual'),
    degree: nullableString(process.degree, 'grau'),
    court: nullableString(process.court, 'órgão julgador'),
    filingDate: nullableString(process.filingDate, 'data de ajuizamento'),
    secrecyLevel: nullableString(process.secrecyLevel, 'nível de sigilo'),
    system: nullableString(process.system, 'sistema processual'),
    lastConsultedAt: nullableString(
      process.lastConsultedAt,
      'última consulta do processo'
    ),
    sourceUpdatedAt: nullableString(
      process.sourceUpdatedAt,
      'última atualização da fonte'
    ),
    lastMovement,
    hasNews: process.hasNews === true,
    newMovementCount: nonNegativeInteger(
      process.newMovementCount,
      'novidades do processo'
    ),
    responsibleName: nullableString(
      process.responsibleName,
      'responsável pelo processo'
    ),
    nextAction: nullableString(process.nextAction, 'próxima providência'),
    status: registeredStatus,
    state,
    recentMovement: lastMovement,
  };
}

export function parseClientPortfolioRow(
  value: unknown
): ClientPortfolioReadModel {
  const row = record(value, 'carteira do cliente');
  if (!Array.isArray(row.processes)) {
    throw new Error('Resposta inválida para processos da carteira.');
  }
  return {
    clientId: requiredString(row.clientId, 'cliente da carteira'),
    clientName: requiredString(row.clientName, 'nome do cliente'),
    processCount: nonNegativeInteger(
      row.processCount,
      'quantidade de processos'
    ),
    noveltyCount: nonNegativeInteger(
      row.noveltyCount,
      'quantidade de novidades'
    ),
    notUpdatedCount: nonNegativeInteger(
      row.notUpdatedCount,
      'quantidade não atualizada'
    ),
    failureCount: nonNegativeInteger(row.failureCount, 'quantidade com falha'),
    reviewCount: nonNegativeInteger(row.reviewCount, 'quantidade em revisão'),
    lastConsultedAt: nullableString(row.lastConsultedAt, 'última consulta'),
    lastSourceUpdatedAt: nullableString(
      row.lastSourceUpdatedAt,
      'última atualização da fonte'
    ),
    processes: row.processes.map(parseProcess),
  };
}

function parseDetail(value: unknown): ClientPortfolioProcessDetail {
  const detail = record(value, 'detalhes do processo');
  const process = parseProcess(detail);
  const subjects = detail.subjects;
  const parties = detail.parties;
  const movements = detail.movements;
  if (
    !Array.isArray(subjects) ||
    subjects.some((subject) => typeof subject !== 'string')
  ) {
    throw new Error('Resposta inválida para assuntos do processo.');
  }
  if (!Array.isArray(parties)) {
    throw new Error('Resposta inválida para partes do processo.');
  }
  if (!Array.isArray(movements)) {
    throw new Error('Resposta inválida para movimentações do processo.');
  }
  return {
    ...process,
    subjects,
    parties: parties.map((party) => {
      const parsed = record(party, 'parte do processo');
      return {
        name: requiredString(parsed.name, 'nome da parte'),
        role: requiredString(parsed.role, 'papel da parte'),
      };
    }),
    movements: movements.map((movement) =>
      parseMovement(movement, 'movimentação do processo')
    ),
  };
}

function parseProgress(value: unknown): ClientPortfolioRefreshProgress | null {
  if (value === null || value === undefined) return null;
  const progress = record(value, 'progresso da atualização');
  if (
    progress.state !== 'queued' &&
    progress.state !== 'running' &&
    progress.state !== 'completed' &&
    progress.state !== 'completed_with_issues'
  ) {
    throw new Error('Resposta inválida para estado do lote.');
  }
  return {
    state: progress.state,
    totalCount: nonNegativeInteger(progress.totalCount, 'total do lote'),
    eligibleCount: nonNegativeInteger(
      progress.eligibleCount,
      'processos elegíveis do lote'
    ),
    skippedCount: nonNegativeInteger(
      progress.skippedCount,
      'processos ignorados do lote'
    ),
    pendingCount: nonNegativeInteger(
      progress.pendingCount,
      'pendentes do lote'
    ),
    runningCount: nonNegativeInteger(
      progress.runningCount,
      'em execução do lote'
    ),
    completedCount: nonNegativeInteger(
      progress.completedCount,
      'concluídos do lote'
    ),
    noveltyCount: nonNegativeInteger(
      progress.noveltyCount,
      'novidades do lote'
    ),
    unchangedCount: nonNegativeInteger(
      progress.unchangedCount,
      'sem novidade do lote'
    ),
    failureCount: nonNegativeInteger(progress.failureCount, 'falhas do lote'),
    reviewCount: nonNegativeInteger(progress.reviewCount, 'revisões do lote'),
    lastUpdatedAt: nullableString(
      progress.lastUpdatedAt,
      'última atualização do lote'
    ),
  };
}

export async function getClientPortfolioReadModels(
  supabase: PortfolioDatabaseClient,
  clientId?: string,
  filters?: Omit<ClientPortfolioGridFilters, 'clientId'>
): Promise<ClientPortfolioReadModel[]> {
  const hasGridFilters = Boolean(
    filters?.search || filters?.state || typeof filters?.isPublic === 'boolean'
  );
  const { data, error } = hasGridFilters
    ? await supabase.rpc('get_client_portfolio_grid', {
        ...(clientId ? { p_client_id: clientId } : {}),
        ...(filters?.search ? { p_search: filters.search } : {}),
        ...(filters?.state ? { p_state: filters.state } : {}),
        ...(typeof filters?.isPublic === 'boolean'
          ? { p_is_public: filters.isPublic }
          : {}),
      })
    : await supabase.rpc('get_client_portfolio_read_model', {
        p_client_id: clientId,
      });
  if (error)
    throw new Error('Não foi possível carregar a carteira do cliente.');
  return (data ?? []).map(parseClientPortfolioRow);
}

export async function getClientPortfolioReadModel(
  supabase: PortfolioDatabaseClient,
  clientId: string
): Promise<ClientPortfolioReadModel | null> {
  const models = await getClientPortfolioReadModels(supabase, clientId);
  return models[0] ?? null;
}

export async function getClientPortfolioProcessDetail(
  supabase: PortfolioDatabaseClient,
  processId: string
): Promise<ClientPortfolioProcessDetail | null> {
  const { data, error } = await supabase.rpc(
    'get_client_portfolio_process_detail',
    { p_process_id: processId }
  );
  if (error)
    throw new Error('Não foi possível carregar os detalhes do processo.');
  return data === null ? null : parseDetail(data);
}

export async function getClientPortfolioRefreshProgress(
  supabase: PortfolioDatabaseClient,
  clientId: string
): Promise<ClientPortfolioRefreshProgress | null> {
  const { data, error } = await supabase.rpc(
    'get_client_portfolio_refresh_progress',
    { p_client_id: clientId }
  );
  if (error)
    throw new Error('Não foi possível carregar o progresso da atualização.');
  return parseProgress(data);
}
