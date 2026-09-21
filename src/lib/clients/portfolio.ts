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

export type ClientPortfolioProcess = {
  processId: string;
  cnjNumber: string;
  tribunal: string;
  isPublic: boolean;
  status: string;
  state: ClientPortfolioProcessState;
  lastConsultedAt: string | null;
  sourceUpdatedAt: string | null;
  hasNews: boolean;
  newMovementCount: number;
  recentMovement: {
    date: string;
    description: string | null;
  } | null;
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

function parseRecentMovement(
  value: unknown
): ClientPortfolioProcess['recentMovement'] {
  if (value === null || value === undefined) return null;
  const movement = record(value, 'movimentação recente');
  return {
    date: requiredString(movement.date, 'data da movimentação recente'),
    description: nullableString(
      movement.description,
      'descrição da movimentação recente'
    ),
  };
}

function parseProcess(value: unknown): ClientPortfolioProcess {
  const process = record(value, 'processo da carteira');
  return {
    processId: requiredString(process.processId, 'processo da carteira'),
    cnjNumber: requiredString(process.cnjNumber, 'CNJ do processo'),
    tribunal: requiredString(process.tribunal, 'tribunal do processo'),
    isPublic: process.isPublic === true,
    status: requiredString(process.status, 'situação do processo'),
    state: processState(process.state),
    lastConsultedAt: nullableString(
      process.lastConsultedAt,
      'última consulta do processo'
    ),
    sourceUpdatedAt: nullableString(
      process.sourceUpdatedAt,
      'última atualização da fonte'
    ),
    hasNews: process.hasNews === true,
    newMovementCount: nonNegativeInteger(
      process.newMovementCount,
      'novidades do processo'
    ),
    recentMovement: parseRecentMovement(process.recentMovement),
  };
}

export function parseClientPortfolioRow(
  value: unknown
): ClientPortfolioReadModel {
  const row = record(value, 'carteira do cliente');
  const processes = row.processes;
  if (!Array.isArray(processes)) {
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
    processes: processes.map(parseProcess),
  };
}

export async function getClientPortfolioReadModels(
  supabase: PortfolioDatabaseClient,
  clientId?: string
): Promise<ClientPortfolioReadModel[]> {
  const { data, error } = await supabase.rpc(
    'get_client_portfolio_read_model',
    { p_client_id: clientId }
  );
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
