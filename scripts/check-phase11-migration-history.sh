#!/usr/bin/env bash
set -euo pipefail
MIGRATION="supabase/migrations/20260827000003_phase_11_failures_notifications.sql"
if [[ "$(head -n 1 "${MIGRATION}")" != "SET lock_timeout = '2s';" ]]; then
  echo "A migration da Fase 11 não começa com SET lock_timeout = '2s';" >&2
  exit 1
fi
for required in \
  "CREATE TABLE public.failure_incident" \
  "CREATE TABLE public.failure_occurrence" \
  "CREATE TABLE public.notification_outbox" \
  "phase11_request_failure_reprocess" \
  "phase11_list_failure_incidents" \
  "phase11_reconcile_success_internal"; do
  if ! grep -q "${required}" "${MIGRATION}"; then
    echo "Objeto obrigatório ausente na migration da Fase 11: ${required}" >&2
    exit 1
  fi
done
if grep -Eq "CREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?FUNCTION[[:space:]]+public\.phase9_complete_query_execution|DROP[[:space:]]+TABLE[[:space:]]+public\.(failure_incident|failure_occurrence|notification_outbox)" "${MIGRATION}"; then
  echo "A migration da Fase 11 tenta reescrever a conclusão da Fase 9 ou remover evidência." >&2
  exit 1
fi
echo "phase11-migration-history=PASS"
echo "migration_00003=additive"
