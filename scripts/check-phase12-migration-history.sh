#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="${ROOT_DIR}/supabase/migrations/20260827000005_phase_12_weekly_reports.sql"
BASELINE="aa96eca762a47a1497203758fb62513e190139e5"

[[ -f "${MIGRATION}" ]] || { echo 'Migration 00005 não encontrada.' >&2; exit 1; }
[[ "$(head -n 1 "${MIGRATION}")" == "SET lock_timeout = '2s';" ]] || {
  echo 'A migration 00005 deve começar com SET lock_timeout = '\''2s'\'';.' >&2
  exit 1
}

for required in weekly_report report_version report_process report_party report_command_idempotency \
  phase12_generate_weekly_report phase12_create_editorial_version phase12_restore_report_version \
  phase12_submit_report phase12_return_report_to_draft phase12_approve_report phase12_cancel_report; do
  grep -Eq "(CREATE TABLE public\\.${required}|CREATE OR REPLACE FUNCTION public\\.${required})" "${MIGRATION}" || {
    echo "Objeto obrigatório ausente na migration 00005: ${required}" >&2
    exit 1
  }
done

SQL_WITHOUT_COMMENTS="$(sed -E '/^[[:space:]]*--/d; s/--.*$//' "${MIGRATION}")"
if grep -Eiq "CREATE TABLE public\\.(weekly_report|report_version|report_process|report_party).*sent|status.*sent" <<<"${SQL_WITHOUT_COMMENTS}"; then
  echo 'A Fase 12 não pode criar estado sent.' >&2
  exit 1
fi
if grep -Eiq "\\b(pdf|smtp|webhook|recipient|destination|delivery)\\b|DataJud real|CNJ real" <<<"${SQL_WITHOUT_COMMENTS}"; then
  echo 'A migration contém fronteira proibida da Fase 12.' >&2
  exit 1
fi

for historical in \
  supabase/migrations/20260826000011_phase_9_scheduler_queue_snapshots.sql \
  supabase/migrations/20260826000012_phase_9_stale_lease_hardening.sql \
  supabase/migrations/20260827000001_phase_10_comparison_detection.sql \
  supabase/migrations/20260827000002_phase_10_comparison_hardening.sql \
  supabase/migrations/20260827000003_phase_11_failures_notifications.sql \
  supabase/migrations/20260827000004_phase_11_failures_notifications_hardening.sql; do
  git diff --quiet "${BASELINE}" -- "${historical}" || {
    echo "Migration histórica alterada indevidamente: ${historical}" >&2
    exit 1
  }
done

printf '%s\n' \
  'phase12-migration-history=PASS' \
  'phase12-migration=20260827000005_phase_12_weekly_reports.sql' \
  'historical-migrations=IMMUTABLE' \
  'phase12-no-send-state=PASS'
