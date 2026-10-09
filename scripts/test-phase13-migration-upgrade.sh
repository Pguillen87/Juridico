#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI=(npx --no-install supabase)
PRETTIER=(npx --no-install prettier)
source "${ROOT_DIR}/scripts/lib/native-cli-path.sh"
TMP_DIR="$(mktemp -d "${ROOT_DIR}/.migration-upgrade.XXXXXX")"
F12_PROJECT_DIR="${TMP_DIR}/f12-project"
UPGRADE_PROJECT_DIR="${TMP_DIR}/upgrade-project"
FINGERPRINT_SQL="${TMP_DIR}/fingerprint.sql"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat >"${FINGERPRINT_SQL}" <<'SQL'
SELECT md5(
  coalesce(string_agg(
    table_name || '|' || column_name || '|' || data_type || '|' || is_nullable,
    E'\n' ORDER BY table_name, ordinal_position
  ), '')
  || coalesce((
    SELECT string_agg(version, ',' ORDER BY version)
      FROM supabase_migrations.schema_migrations
     WHERE version >= '20260827000007'
  ), '')
) AS fingerprint
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'client_contact', 'report_artifact', 'email_delivery',
    'email_delivery_attempt', 'email_delivery_retry_command'
  );
SQL

run_supabase() { run_supabase_with_native_paths "$@"; }

fingerprint() {
  local workdir="$1"
  local output="${TMP_DIR}/fingerprint-$(basename "${workdir}").txt"
  run_supabase_read_with_native_paths db query --local --workdir "${ROOT_DIR}" \
    --file "${FINGERPRINT_SQL}" >"${output}"
  local value
  value="$(grep -Eo '[0-9a-f]{32}' "${output}" | tail -1 || true)"
  [[ "${value}" =~ ^[0-9a-f]{32}$ ]] || { cat "${output}" >&2; exit 1; }
  printf '%s' "${value}"
}

generate_types() {
  local output="$1"
  run_supabase_read_with_native_paths gen types typescript --local --workdir "${ROOT_DIR}" >"${output}"
  "${PRETTIER[@]}" --write "$(native_cli_path "${output}")" >/dev/null
}

copy_post_f13_migrations() {
  local target_dir="$1"
  cp "${ROOT_DIR}/supabase/migrations/20260827000007_phase_13_pdf_delivery.sql" \
    "${target_dir}/supabase/migrations/20260827000007_phase_13_pdf_delivery.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260827000008_phase_13_delivery_hardening.sql" \
    "${target_dir}/supabase/migrations/20260827000008_phase_13_delivery_hardening.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260905000001_realignment1_manual_refresh.sql" \
    "${target_dir}/supabase/migrations/20260905000001_realignment1_manual_refresh.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260920000001_client_portfolio_read_model.sql" \
    "${target_dir}/supabase/migrations/20260920000001_client_portfolio_read_model.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260920000002_phase11_lint_hardening.sql" \
    "${target_dir}/supabase/migrations/20260920000002_phase11_lint_hardening.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260920000003_phase10_public_comparison.sql" \
    "${target_dir}/supabase/migrations/20260920000003_phase10_public_comparison.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260921152859_client_portfolio_batch_refresh.sql" \
    "${target_dir}/supabase/migrations/20260921152859_client_portfolio_batch_refresh.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260922013204_process_deactivation_visibility.sql" \
    "${target_dir}/supabase/migrations/20260922013204_process_deactivation_visibility.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260922200803_portfolio_grid_filters.sql" \
    "${target_dir}/supabase/migrations/20260922200803_portfolio_grid_filters.sql"
  cp "${ROOT_DIR}/supabase/migrations/20260922202628_portfolio_grid_read_model_fields.sql" \
    "${target_dir}/supabase/migrations/20260922202628_portfolio_grid_read_model_fields.sql"
}

copy_post_f13_tests() {
  local target_dir="$1"
  cp "${ROOT_DIR}/supabase/tests/database/17_phase_13_pdf_delivery.test.sql" \
    "${target_dir}/supabase/tests/database/17_phase_13_pdf_delivery.test.sql"
  cp "${ROOT_DIR}/supabase/tests/database/18_realignment1_manual_refresh.test.sql" \
    "${target_dir}/supabase/tests/database/18_realignment1_manual_refresh.test.sql"
  cp "${ROOT_DIR}/supabase/tests/database/19_client_portfolio_read_model.test.sql" \
    "${target_dir}/supabase/tests/database/19_client_portfolio_read_model.test.sql"
  cp "${ROOT_DIR}/supabase/tests/database/20_client_portfolio_batch_refresh.test.sql" \
    "${target_dir}/supabase/tests/database/20_client_portfolio_batch_refresh.test.sql"
  cp "${ROOT_DIR}/supabase/tests/database/21_client_process_deactivation.test.sql" \
    "${target_dir}/supabase/tests/database/21_client_process_deactivation.test.sql"
  cp "${ROOT_DIR}/supabase/tests/database/22_portfolio_grid_filters.test.sql" \
    "${target_dir}/supabase/tests/database/22_portfolio_grid_filters.test.sql"
}

echo 'phase13-upgrade=full-reset'
run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null
wait_for_supabase_readiness "${ROOT_DIR}"
full_fingerprint="$(fingerprint "${ROOT_DIR}")"
generate_types "${TMP_DIR}/full-types.ts"
run_supabase test db --local --workdir "${ROOT_DIR}" >/dev/null
printf 'full_reset_fingerprint=%s\nfull_reset_pgTap=PASS\n' "${full_fingerprint}"

echo 'phase13-upgrade=prepare-f12-schema'
mkdir -p "${F12_PROJECT_DIR}"
cp -R "${ROOT_DIR}/supabase" "${F12_PROJECT_DIR}/supabase"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260827000007_phase_13_pdf_delivery.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260827000008_phase_13_delivery_hardening.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260905000001_realignment1_manual_refresh.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260920000001_client_portfolio_read_model.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260920000002_phase11_lint_hardening.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260920000003_phase10_public_comparison.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260921152859_client_portfolio_batch_refresh.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260922013204_process_deactivation_visibility.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260922200803_portfolio_grid_filters.sql"
rm -f "${F12_PROJECT_DIR}/supabase/migrations/20260922202628_portfolio_grid_read_model_fields.sql"
rm -f "${F12_PROJECT_DIR}/supabase/tests/database/17_phase_13_pdf_delivery.test.sql"
rm -f "${F12_PROJECT_DIR}/supabase/tests/database/18_realignment1_manual_refresh.test.sql"
rm -f "${F12_PROJECT_DIR}/supabase/tests/database/19_client_portfolio_read_model.test.sql"
rm -f "${F12_PROJECT_DIR}/supabase/tests/database/20_client_portfolio_batch_refresh.test.sql"
rm -f "${F12_PROJECT_DIR}/supabase/tests/database/21_client_process_deactivation.test.sql"
rm -f "${F12_PROJECT_DIR}/supabase/tests/database/22_portfolio_grid_filters.test.sql"
run_supabase db reset --local --workdir "${F12_PROJECT_DIR}" --yes >/dev/null
wait_for_supabase_readiness "${ROOT_DIR}"
run_supabase test db --local --workdir "${F12_PROJECT_DIR}" >/dev/null
run_supabase db reset --local --workdir "${F12_PROJECT_DIR}" --yes >/dev/null
wait_for_supabase_readiness "${ROOT_DIR}"
echo 'f12_schema=PASS'

echo 'phase13-upgrade=apply-00007-and-00008'
mkdir -p "${UPGRADE_PROJECT_DIR}"
cp -R "${F12_PROJECT_DIR}/supabase" "${UPGRADE_PROJECT_DIR}/supabase"
copy_post_f13_migrations "${UPGRADE_PROJECT_DIR}"
copy_post_f13_tests "${UPGRADE_PROJECT_DIR}"
run_supabase db push --local --workdir "${UPGRADE_PROJECT_DIR}" --yes --include-all >/dev/null
upgrade_fingerprint="$(fingerprint "${UPGRADE_PROJECT_DIR}")"
generate_types "${TMP_DIR}/upgrade-types.ts"
run_supabase test db --local --workdir "${UPGRADE_PROJECT_DIR}" >/dev/null

run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null
wait_for_supabase_readiness "${ROOT_DIR}"

if [[ "${full_fingerprint}" != "${upgrade_fingerprint}" ]]; then
  echo "Fingerprint diverge: ${full_fingerprint} != ${upgrade_fingerprint}." >&2
  exit 1
fi
if ! cmp -s "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts"; then
  echo 'Tipos gerados divergem.' >&2
  diff -u "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts" >&2 || true
  exit 1
fi

printf 'upgrade_fingerprint=%s\nupgrade_pgTap=PASS\nupgrade_types=PASS\nphase13-migration-upgrade=PASS\n' \
  "${upgrade_fingerprint}"
