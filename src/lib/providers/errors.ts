import {
  PROVIDER_FAILURE_CODES,
  type ProviderFailureCode,
  type ProviderKind,
} from './contract';

export const PROVIDER_ERROR_CODES = [
  'provider_not_registered',
  'capability_not_supported',
  'operation_not_supported',
  'manual_evidence_missing',
  'manual_process_mismatch',
  'timeout',
] as const;
export type ProviderErrorCode = (typeof PROVIDER_ERROR_CODES)[number];

export const RETRYABLE_FAILURES: ReadonlySet<ProviderFailureCode> = new Set([
  'source_unavailable',
  'rate_limited',
  'timeout',
]);

export function isProviderFailureCode(
  value: string
): value is ProviderFailureCode {
  return (PROVIDER_FAILURE_CODES as readonly string[]).includes(value);
}

export function isProviderErrorCode(value: string): value is ProviderErrorCode {
  return (PROVIDER_ERROR_CODES as readonly string[]).includes(value);
}

export function sanitizeProviderMessage(code: ProviderFailureCode): string {
  switch (code) {
    case 'not_supported':
      return 'A capability solicitada não é suportada por esta fonte.';
    case 'not_found':
      return 'A fonte não encontrou a referência solicitada.';
    case 'rate_limited':
      return 'A fonte aplicou limite temporário de requisições.';
    case 'timeout':
      return 'A fonte não respondeu dentro do tempo permitido.';
    case 'source_unavailable':
      return 'A fonte está indisponível no momento.';
    case 'manual_review_required':
      return 'A observação exige revisão manual antes de qualquer decisão.';
    case 'technical_failure':
      return 'Não foi possível interpretar a resposta da fonte.';
  }
}

export interface FailureMetadataInput {
  readonly providerId: string;
  readonly providerKind: ProviderKind;
  readonly adapterVersion: string;
  readonly observedAt: string;
  readonly durationMs?: number;
}

export function failurePolicy(code: ProviderFailureCode): {
  readonly retryable: boolean;
  readonly retryAfterMs?: number;
} {
  if (code === 'rate_limited') return { retryable: true, retryAfterMs: 60_000 };
  return { retryable: RETRYABLE_FAILURES.has(code) };
}
