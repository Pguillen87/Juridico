#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION_00005="${ROOT_DIR}/supabase/migrations/20260827000005_phase_12_weekly_reports.sql"
MIGRATION_00006="${ROOT_DIR}/supabase/migrations/20260827000006_phase_12_weekly_reports_hardening.sql"
MIGRATION_00007="${ROOT_DIR}/supabase/migrations/20260827000007_phase_13_pdf_delivery.sql"
MIGRATION_00008="${ROOT_DIR}/supabase/migrations/20260827000008_phase_13_delivery_hardening.sql"
BASELINE="fcbf3c76521ce98f1a2e266282866077cdac3719"
EXPECTED_00005="c8f13774c0707d8502c6348283f2adf0e2673149"
EXPECTED_00006="2b61ff7a1e857e5ee395a602dda20d83498e6720"
EXPECTED_00007_SHA1="6255e982431f7a52c795a19c6f6a5020303c9e4d"
for file in "${MIGRATION_00005}" "${MIGRATION_00006}" "${MIGRATION_00007}" "${MIGRATION_00008}"; do
  [[ -f "${file}" ]] || { echo "Migration ausente: ${file}" >&2; exit 1; }
done
[[ "$(sed 's/\r$//' "${MIGRATION_00005}" | git hash-object --stdin)" == "${EXPECTED_00005}" ]] || { echo '00005 diverge do blob aprovado.' >&2; exit 1; }
[[ "$(sed 's/\r$//' "${MIGRATION_00006}" | git hash-object --stdin)" == "${EXPECTED_00006}" ]] || { echo '00006 diverge do blob aprovado.' >&2; exit 1; }
[[ "$(head -n 1 "${MIGRATION_00007}")" == "SET lock_timeout = '2s';" ]] || { echo '00007 deve começar com SET lock_timeout = '\''2s'\'';.' >&2; exit 1; }
[[ "$(head -n 1 "${MIGRATION_00008}")" == "SET lock_timeout = '2s';" ]] || { echo '00008 deve começar com SET lock_timeout = '\''2s'\'';.' >&2; exit 1; }
[[ "$(sha1sum "${MIGRATION_00007}" | awk '{print $1}')" == "${EXPECTED_00007_SHA1}" ]] || { echo '00007 publicado foi alterado.' >&2; exit 1; }

# F9--F12 are historical once the F12 baseline was approved; none may change.
for historical in \
  supabase/migrations/20260826000011_phase_9_scheduler_queue_snapshots.sql \
  supabase/migrations/20260826000012_phase_9_stale_lease_hardening.sql \
  supabase/migrations/20260827000001_phase_10_comparison_detection.sql \
  supabase/migrations/20260827000002_phase_10_comparison_hardening.sql \
  supabase/migrations/20260827000003_phase_11_failures_notifications.sql \
  supabase/migrations/20260827000004_phase_11_failures_notifications_hardening.sql; do
  expected_historical="$(git rev-parse "${BASELINE}:${historical}")"
  actual_historical="$(sed 's/\r$//' "${ROOT_DIR}/${historical}" | git hash-object --stdin)"
  [[ "${actual_historical}" == "${expected_historical}" ]] || { echo "Migration histórica alterada: ${historical}" >&2; exit 1; }
done

git cat-file -e "${EXPECTED_00005}" || { echo 'Blob aprovado de 00005 não está no histórico.' >&2; exit 1; }
git cat-file -e "${EXPECTED_00006}" || { echo 'Blob aprovado de 00006 não está no histórico.' >&2; exit 1; }
printf '%s\n' \
  'phase13-migration-history=PASS' \
  "phase12-00005-blob=${EXPECTED_00005}" \
  "phase12-00006-blob=${EXPECTED_00006}" \
  'phase13-00007-lock-timeout=PASS' \
  'historical-migrations=IMMUTABLE'
