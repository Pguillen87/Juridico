import {
  CLIENT_PORTFOLIO_STATES,
  type ClientPortfolioProcessState,
} from '@/lib/clients/portfolio';

export type PortfolioGridFilters = {
  clientId?: string;
  search?: string;
  state?: ClientPortfolioProcessState;
  isPublic?: boolean;
};

type SearchParams = Record<string, string | string[] | undefined>;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function validState(
  value: string | undefined
): ClientPortfolioProcessState | undefined {
  return value && (CLIENT_PORTFOLIO_STATES as readonly string[]).includes(value)
    ? (value as ClientPortfolioProcessState)
    : undefined;
}

export function parsePortfolioGridFilters(
  params: SearchParams
): PortfolioGridFilters {
  const clientId = firstValue(params.clientId);
  const search = firstValue(params.q)?.trim().toLocaleLowerCase('pt-BR');
  const state = validState(firstValue(params.state));
  const visibility = firstValue(params.visibility);

  return {
    ...(clientId && UUID_PATTERN.test(clientId) ? { clientId } : {}),
    ...(search ? { search } : {}),
    ...(state ? { state } : {}),
    ...(visibility === 'public'
      ? { isPublic: true }
      : visibility === 'private'
        ? { isPublic: false }
        : {}),
  };
}
