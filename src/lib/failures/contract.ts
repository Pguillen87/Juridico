export const FAILURE_CLASSES = [
  'provider_transient',
  'provider_permanent',
  'provider_manual_review',
  'persistence',
  'comparison',
  'scheduler',
  'worker',
  'notification',
] as const;

export type FailureClass = (typeof FAILURE_CLASSES)[number];
export type FailurePriority = 'low' | 'medium' | 'high';
export type FailureIncidentStatus = 'open' | 'resolved';
export type FailureEventKind =
  | 'failure_observed'
  | 'auto_resolved'
  | 'manual_resolved'
  | 'reopened'
  | 'manual_reprocess_requested'
  | 'assignee_changed'
  | 'operator_note_added';

export const FAILURE_CODES = [
  'provider_not_registered',
  'capability_not_supported',
  'operation_not_supported',
  'manual_evidence_missing',
  'manual_process_mismatch',
  'timeout',
  'datajud_input_schema_invalid',
  'datajud_timeout',
  'datajud_dns_failure',
  'datajud_network_failure',
  'datajud_rate_limited',
  'datajud_source_unavailable',
  'datajud_not_found',
  'datajud_http_failure',
  'datajud_payload_too_large',
  'datajud_schema_invalid',
  'datajud_process_mismatch',
  'datajud_process_not_eligible',
  'datajud_payload_sanitization_failed',
  'provider_persistence_failed',
  'provider_backend_unauthorized',
  'provider_backend_unavailable',
  'worker_provider_execution_failed',
  'worker_lease_expired',
  'comparison_persistence_failed',
  'scheduler_failure',
  'worker_failure',
  'outbox_persistence_failed',
  'audit_failure',
  'not_found',
  'not_supported',
  'manual_review_required',
] as const;

export type FailureCode = (typeof FAILURE_CODES)[number];

export type FailureIncidentRow = {
  incident_id: string;
  office_id: string;
  process_id: string | null;
  origin: string;
  provider_id: string | null;
  capability: string | null;
  failure_stage: string;
  failure_class: FailureClass;
  failure_code: FailureCode;
  status: FailureIncidentStatus;
  first_seen_at: string;
  last_seen_at: string;
  occurrence_count: number;
  assigned_to_user_id: string | null;
  operational_priority: FailurePriority;
  next_action_code:
    'resolved' | 'await_retry' | 'reprocess' | 'review_manually';
  next_attempt_at: string | null;
  current_attempt_number: number | null;
  last_attempt_number: number | null;
};

export type FailureOccurrenceRow = {
  id: string;
  incident_id: string;
  event_kind: FailureEventKind;
  origin: string;
  failure_stage: string | null;
  failure_class: FailureClass | null;
  failure_code: FailureCode | null;
  source_type: string;
  source_id: string | null;
  query_execution_id: string | null;
  query_job_id: string | null;
  attempt_number: number | null;
  observed_job_status: string | null;
  sanitized_message_code: string | null;
  operator_note_sanitized: string | null;
  resolution_note_sanitized: string | null;
  event_actor_user_id: string | null;
  previous_assignee_user_id: string | null;
  new_assignee_user_id: string | null;
  occurred_at: string;
};

export type FailureAssignee = {
  id: string;
  name: string;
  role: 'lawyer' | 'operator';
};

export function failureClassLabel(value: FailureClass): string {
  return {
    provider_transient: 'Fonte temporariamente indisponível',
    provider_permanent: 'Falha não recuperável automaticamente',
    provider_manual_review: 'Revisão manual necessária',
    persistence: 'Persistência operacional',
    comparison: 'Comparação',
    scheduler: 'Agendamento',
    worker: 'Worker',
    notification: 'Notificação interna',
  }[value];
}

export function failureCodeLabel(value: FailureCode | null): string {
  if (!value) return 'Sem código de falha';
  return value.replaceAll('_', ' ');
}

export function attemptLabel(attempt: number | null): string {
  return attempt === null ? 'Não se aplica' : `Tentativa ${attempt}`;
}

export function isFailureClass(value: string): value is FailureClass {
  return (FAILURE_CLASSES as readonly string[]).includes(value);
}

export function isFailureCode(value: string): value is FailureCode {
  return (FAILURE_CODES as readonly string[]).includes(value);
}

export function failureClassFromCode(code: string): FailureClass {
  if (
    [
      'timeout',
      'datajud_timeout',
      'datajud_dns_failure',
      'datajud_network_failure',
      'datajud_rate_limited',
      'datajud_source_unavailable',
      'provider_backend_unavailable',
    ].includes(code)
  )
    return 'provider_transient';
  if (['manual_review_required', 'manual_evidence_missing'].includes(code))
    return 'provider_manual_review';
  if (['provider_persistence_failed'].includes(code)) return 'persistence';
  if (['comparison_persistence_failed'].includes(code)) return 'comparison';
  if (['scheduler_failure'].includes(code)) return 'scheduler';
  if (
    [
      'worker_failure',
      'worker_lease_expired',
      'worker_provider_execution_failed',
    ].includes(code)
  )
    return 'worker';
  if (['outbox_persistence_failed', 'audit_failure'].includes(code))
    return 'notification';
  return 'provider_permanent';
}

export function sanitizeFailureMessage(value: string | undefined): string {
  if (!value) return 'Não foi possível concluir a operação.';
  if (value.includes('permission denied'))
    return 'Você não tem autorização para esta operação.';
  if (value.includes('not found'))
    return 'A falha não foi encontrada no seu escritório.';
  if (value.includes('eligible'))
    return 'A falha não está elegível para esta operação.';
  if (value.includes('duplicate') || value.includes('23505'))
    return 'Esta operação já foi registrada.';
  if (value.includes('invalid') || value.includes('22023'))
    return 'Os dados informados são inválidos.';
  return 'Não foi possível concluir a operação.';
}
