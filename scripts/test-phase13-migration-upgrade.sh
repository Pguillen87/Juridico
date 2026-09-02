#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI=(npx --no-install supabase)
PRETTIER=(npx --no-install prettier)
TMP_DIR="$(mktemp -d)"
MIGRATION_00007="${ROOT_DIR}/supabase/migrations/20260827000007_phase_13_pdf_delivery.sql"
MIGRATION_00007_BACKUP="${TMP_DIR}/20260827000007_phase_13_pdf_delivery.sql"
MIGRATION_00008="${ROOT_DIR}/supabase/migrations/20260827000008_phase_13_delivery_hardening.sql"
MIGRATION_00008_BACKUP="${TMP_DIR}/20260827000008_phase_13_delivery_hardening.sql"
FINGERPRINT_SQL="${TMP_DIR}/fingerprint.sql"
cleanup() {
  if [[ ! -f "${MIGRATION_00007}" && -f "${MIGRATION_00007_BACKUP}" ]]; then cp "${MIGRATION_00007_BACKUP}" "${MIGRATION_00007}"; fi
  if [[ ! -f "${MIGRATION_00008}" && -f "${MIGRATION_00008_BACKUP}" ]]; then cp "${MIGRATION_00008_BACKUP}" "${MIGRATION_00008}"; fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT
cat >"${FINGERPRINT_SQL}" <<'SQL'
SELECT md5(coalesce(string_agg(table_name||'|'||column_name||'|'||data_type||'|'||is_nullable, E'\n' ORDER BY table_name, ordinal_position), '') || coalesce((SELECT string_agg(version, ',' ORDER BY version) FROM supabase_migrations.schema_migrations WHERE version >= '20260827000007'), '')) AS fingerprint
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('client_contact','report_artifact','email_delivery','email_delivery_attempt','email_delivery_retry_command');
SQL
run_supabase() { "${CLI[@]}" "$@"; }
fingerprint() {
  local workdir="$1"
  local output="${TMP_DIR}/fingerprint-$(basename "${workdir}").txt"
  local value
  run_supabase db query --local --workdir "${workdir}" --file "${FINGERPRINT_SQL}" >"${output}"
  value="$(grep -Eo '[0-9a-f]{32}' "${output}" | tail -1 || true)"
  [[ "${value}" =~ ^[0-9a-f]{32}$ ]] || { cat "${output}" >&2; exit 1; }
  printf '%s' "${value}"
}
generate_types() { run_supabase gen types typescript --local --workdir "$1" >"$2"; "${PRETTIER[@]}" --write "$2" >/dev/null; }
printf '%s\n' 'phase13-upgrade=full-reset'
run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null
full_fingerprint="$(fingerprint "${ROOT_DIR}")"
generate_types "${ROOT_DIR}" "${TMP_DIR}/full-types.ts"
run_supabase test db --local --workdir "${ROOT_DIR}" >/dev/null
printf 'full_reset_fingerprint=%s\nfull_reset_pgTap=PASS\n' "${full_fingerprint}"
printf '%s\n' 'phase13-upgrade=prepare-f12-schema'
cp "${MIGRATION_00007}" "${MIGRATION_00007_BACKUP}"
cp "${MIGRATION_00008}" "${MIGRATION_00008_BACKUP}"
rm "${MIGRATION_00007}" "${MIGRATION_00008}"
run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null
cp "${MIGRATION_00007_BACKUP}" "${MIGRATION_00007}"
cp "${MIGRATION_00008_BACKUP}" "${MIGRATION_00008}"
printf '%s\n' 'phase13-upgrade=apply-00007-and-00008'
run_supabase db push --local --workdir "${ROOT_DIR}" --yes >/dev/null
upgrade_fingerprint="$(fingerprint "${ROOT_DIR}")"
generate_types "${ROOT_DIR}" "${TMP_DIR}/upgrade-types.ts"
run_supabase test db --local --workdir "${ROOT_DIR}" >/dev/null
if [[ "${full_fingerprint}" != "${upgrade_fingerprint}" ]]; then echo "Fingerprint diverge: ${full_fingerprint} != ${upgrade_fingerprint}." >&2; exit 1; fi
if ! cmp -s "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts"; then echo 'Tipos gerados divergem.' >&2; diff -u "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts" >&2 || true; exit 1; fi
printf 'upgrade_fingerprint=%s\nupgrade_pgTap=PASS\nupgrade_types=PASS\nphase13-migration-upgrade=PASS\n' "${upgrade_fingerprint}"
