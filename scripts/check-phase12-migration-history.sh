#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="${ROOT_DIR}/supabase/migrations/20260827000005_phase_12_weekly_reports.sql"
MIGRATION_00006="${ROOT_DIR}/supabase/migrations/20260827000006_phase_12_weekly_reports_hardening.sql"
MIGRATION_PATH="supabase/migrations/20260827000005_phase_12_weekly_reports.sql"
MIGRATION_00006_PATH="supabase/migrations/20260827000006_phase_12_weekly_reports_hardening.sql"
BASELINE="aa96eca762a47a1497203758fb62513e190139e5"
ORIGINAL_COMMIT="d8a0364202229a46396094d238cfc93fa744dbe8"
ORIGINAL_BLOB="639269dd06423a39a30b0c791bc3c5f248842353"
FIRST_EXCEPTION_COMMIT="9668c759737e16d370da1c01f71681f8b4acbcec"
FIRST_EXCEPTION_BLOB="5b9be2636124b46550da89b5b2a25902b3266261"
SECOND_EXCEPTION_COMMIT="bf5b9621fb067441c8290efa9ccb8d26f2bf68b8"
CANDIDATE_V2_BLOB="c8f13774c0707d8502c6348283f2adf0e2673149"

[[ -f "${MIGRATION}" ]] || { echo 'Migration 00005 não encontrada.' >&2; exit 1; }
[[ -f "${MIGRATION_00006}" ]] || { echo 'Migration 00006 não encontrada.' >&2; exit 1; }
[[ "$(head -n 1 "${MIGRATION}")" == "SET lock_timeout = '2s';" ]] || {
  echo 'A migration 00005 deve começar com SET lock_timeout = '\''2s'\'';.' >&2
  exit 1
}

[[ "$(git rev-parse "${ORIGINAL_COMMIT}:${MIGRATION_PATH}")" == "${ORIGINAL_BLOB}" ]] || {
  echo 'O commit original não aponta para o blob defeituoso esperado.' >&2
  exit 1
}
[[ "$(git rev-parse "${FIRST_EXCEPTION_COMMIT}:${MIGRATION_PATH}")" == "${FIRST_EXCEPTION_BLOB}" ]] || {
  echo 'A primeira exceção não aponta para o blob corrigido esperado.' >&2
  exit 1
}
[[ "$(git rev-parse "${SECOND_EXCEPTION_COMMIT}:${MIGRATION_PATH}")" == "${CANDIDATE_V2_BLOB}" ]] || {
  echo 'A segunda exceção não aponta para o candidato V2 esperado.' >&2
  exit 1
}
[[ "$(git hash-object "${MIGRATION}")" == "${CANDIDATE_V2_BLOB}" ]] || {
  echo 'A 00005 ativa diverge do candidato V2 comprovado.' >&2
  exit 1
}
git cat-file -e "${ORIGINAL_BLOB}" || {
  echo 'O blob original defeituoso não permanece no histórico Git.' >&2
  exit 1
}
V2_DELTA_FILE="$(mktemp)"
trap 'rm -f "${V2_DELTA_FILE}"' EXIT
git -c color.ui=false diff --no-ext-diff --no-textconv --unified=0 "${FIRST_EXCEPTION_BLOB}" "${CANDIDATE_V2_BLOB}" > "${V2_DELTA_FILE}"
[[ "$(grep -Ec '^\+[^+]' "${V2_DELTA_FILE}")" -eq 2 ]] || {
  echo 'A segunda exceção não contém exatamente duas linhas adicionadas.' >&2
  exit 1
}
[[ "$(grep -Ec '^-[^-]' "${V2_DELTA_FILE}")" -eq 0 ]] || {
  echo 'A segunda exceção contém remoções não autorizadas.' >&2
  exit 1
}
grep -Eq '^\+  process_row RECORD;$' "${V2_DELTA_FILE}" || {
  echo 'A segunda exceção não contém process_row RECORD.' >&2
  exit 1
}
grep -Eq '^\+  party_row RECORD;$' "${V2_DELTA_FILE}" || {
  echo 'A segunda exceção não contém party_row RECORD.' >&2
  exit 1
}
[[ "$(head -n 1 "${MIGRATION_00006}")" == "SET lock_timeout = '2s';" ]] || {
  echo 'A migration 00006 deve começar com SET lock_timeout = '\''2s'\'';.' >&2
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
  'phase12-original-blob=639269dd06423a39a30b0c791bc3c5f248842353' \
  'phase12-first-exception-blob=5b9be2636124b46550da89b5b2a25902b3266261' \
  'phase12-candidate-v2-blob=c8f13774c0707d8502c6348283f2adf0e2673149' \
  'phase12-migration=20260827000005_phase_12_weekly_reports.sql' \
  'phase12-migration-00006=20260827000006_phase_12_weekly_reports_hardening.sql' \
  'historical-migrations=IMMUTABLE' \
  'phase12-no-send-state=PASS'
