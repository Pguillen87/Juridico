#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI=(npx --no-install supabase)
PRETTIER=(npx --no-install prettier)
TMP_DIR="$(mktemp -d)"
F10_PROJECT_DIR="${TMP_DIR}/phase10-project"
PRE_F12_PROJECT_DIR="${TMP_DIR}/pre-f12-project"
FINGERPRINT_SQL="${TMP_DIR}/fingerprint.sql"
VERSIONS_SQL="${TMP_DIR}/versions.sql"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat >"${FINGERPRINT_SQL}" <<'SQL'
SELECT md5(concat_ws(E'\n',
  coalesce((
    SELECT string_agg(
      n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || E'\n' || pg_get_functiondef(p.oid),
      E'\n---FUNCTION---\n'
      ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
    )
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'phase12_%'
  ), ''),
  coalesce((
    SELECT string_agg(
      grantee || '|' || routine_schema || '|' || routine_name || '|' || privilege_type || '|' || is_grantable,
      E'\n'
      ORDER BY grantee, routine_schema, routine_name, privilege_type
    )
    FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public' AND routine_name LIKE 'phase12_%'
  ), ''),
  coalesce((
    SELECT string_agg(
      table_schema || '.' || table_name || '|' || column_name || '|' || ordinal_position::text || '|' || data_type || '|' || is_nullable || '|' || coalesce(column_default, ''),
      E'\n'
      ORDER BY table_schema, table_name, ordinal_position
    )
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN ('weekly_report', 'report_version', 'report_process', 'report_party', 'report_command_idempotency')
  ), ''),
  coalesce((
    SELECT string_agg(
      n.nspname || '.' || c.relname || '|' || c.relkind::text || '|' || c.relrowsecurity::text,
      E'\n'
      ORDER BY n.nspname, c.relname
    )
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('weekly_report', 'report_version', 'report_process', 'report_party', 'report_command_idempotency')
  ), ''),
  coalesce((
    SELECT string_agg(
      n.nspname || '.' || c.relname || '|' || con.conname || '|' || con.contype::text || '|' || pg_get_constraintdef(con.oid),
      E'\n'
      ORDER BY n.nspname, c.relname, con.conname
    )
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('weekly_report', 'report_version', 'report_process', 'report_party', 'report_command_idempotency')
  ), ''),
  coalesce((
    SELECT string_agg(
      schemaname || '.' || tablename || '|' || indexname || '|' || indexdef,
      E'\n'
      ORDER BY schemaname, tablename, indexname
    )
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename IN ('weekly_report', 'report_version', 'report_process', 'report_party', 'report_command_idempotency')
  ), ''),
  coalesce((
    SELECT string_agg(
      n.nspname || '.' || c.relname || '|' || pol.polname || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|' || pol.polroles::text || '|' || coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') || '|' || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), ''),
      E'\n'
      ORDER BY n.nspname, c.relname, pol.polname
    )
    FROM pg_policy pol
    JOIN pg_class c ON c.oid = pol.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('weekly_report', 'report_version', 'report_process', 'report_party', 'report_command_idempotency')
  ), ''),
  coalesce((
    SELECT string_agg(
      n.nspname || '.' || c.relname || '|' || t.tgname || '|' || pg_get_triggerdef(t.oid),
      E'\n'
      ORDER BY n.nspname, c.relname, t.tgname
    )
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE NOT t.tgisinternal
      AND n.nspname = 'public'
      AND c.relname IN ('weekly_report', 'report_version', 'report_process', 'report_party', 'report_command_idempotency')
  ), ''),
  coalesce((
    SELECT string_agg(version, E'\n' ORDER BY version)
    FROM supabase_migrations.schema_migrations
    WHERE version >= '20260827000005'
  ), '')
)) AS fingerprint;
SQL

cat >"${VERSIONS_SQL}" <<'SQL'
SELECT version
FROM supabase_migrations.schema_migrations
WHERE version >= '20260827000005'
ORDER BY version;
SQL

run_supabase() { "${CLI[@]}" "$@"; }

fingerprint() {
  local workdir="$1"
  local output="${TMP_DIR}/fingerprint-$(basename "${workdir}").txt"
  run_supabase db query --local --workdir "${workdir}" --file "${FINGERPRINT_SQL}" >"${output}"
  local value
  value="$(grep -Eo '[0-9a-f]{32}' "${output}" | tail -1 || true)"
  [[ "${value}" =~ ^[0-9a-f]{32}$ ]] || { cat "${output}" >&2; exit 1; }
  printf '%s' "${value}"
}

generate_types() {
  local workdir="$1"
  local output="$2"
  run_supabase gen types typescript --local --workdir "${workdir}" >"${output}"
  "${PRETTIER[@]}" --write "${output}" >/dev/null
}

migration_versions() {
  run_supabase db query --local --workdir "$1" --file "${VERSIONS_SQL}"
}

echo 'phase12-upgrade=full-reset'
run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null
full_fingerprint="$(fingerprint "${ROOT_DIR}")"
generate_types "${ROOT_DIR}" "${TMP_DIR}/full-types.ts"
run_supabase test db --local --workdir "${ROOT_DIR}" >/dev/null
echo "full_reset_fingerprint=${full_fingerprint}"
echo 'full_reset_pgTap=PASS'

echo 'phase12-upgrade=prepare-phase10-schema'
mkdir -p "${F10_PROJECT_DIR}"
cp -R "${ROOT_DIR}/supabase" "${F10_PROJECT_DIR}/supabase"
rm -f "${F10_PROJECT_DIR}/supabase/migrations/20260827000005_phase_12_weekly_reports.sql"
rm -f "${F10_PROJECT_DIR}/supabase/migrations/20260827000006_phase_12_weekly_reports_hardening.sql"
rm -f "${F10_PROJECT_DIR}/supabase/migrations/20260827000007_phase_13_pdf_delivery.sql"
run_supabase db reset --local --workdir "${F10_PROJECT_DIR}" --yes >/dev/null

mkdir -p "${PRE_F12_PROJECT_DIR}"
cp -R "${F10_PROJECT_DIR}/supabase" "${PRE_F12_PROJECT_DIR}/supabase"
cp "${ROOT_DIR}/supabase/migrations/20260827000005_phase_12_weekly_reports.sql" \
  "${PRE_F12_PROJECT_DIR}/supabase/migrations/20260827000005_phase_12_weekly_reports.sql"
cp "${ROOT_DIR}/supabase/migrations/20260827000006_phase_12_weekly_reports_hardening.sql" \
  "${PRE_F12_PROJECT_DIR}/supabase/migrations/20260827000006_phase_12_weekly_reports_hardening.sql"

echo 'phase12-upgrade=apply-00005-and-00006'
run_supabase db push --local --workdir "${PRE_F12_PROJECT_DIR}" --yes >/dev/null
versions="$(migration_versions "${PRE_F12_PROJECT_DIR}")"
if ! grep -Fq '20260827000005' <<<"${versions}" || ! grep -Fq '20260827000006' <<<"${versions}"; then
  echo 'As migrations 00005 e 00006 não foram aplicadas no caminho incremental.' >&2
  printf '%s\n' "${versions}" >&2
  exit 1
fi
upgrade_fingerprint="$(fingerprint "${PRE_F12_PROJECT_DIR}")"
generate_types "${PRE_F12_PROJECT_DIR}" "${TMP_DIR}/upgrade-types.ts"
run_supabase test db --local --workdir "${PRE_F12_PROJECT_DIR}" >/dev/null
run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null

if [[ "${full_fingerprint}" != "${upgrade_fingerprint}" ]]; then
  echo "Fingerprint de reset completo diverge do upgrade Fase 11→00005→00006: ${full_fingerprint} != ${upgrade_fingerprint}." >&2
  exit 1
fi
if ! cmp -s "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts"; then
  echo 'Tipos gerados divergem entre reset completo e upgrade Fase 11→00005→00006.' >&2
  diff -u "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts" >&2 || true
  exit 1
fi

echo "upgrade_fingerprint=${upgrade_fingerprint}"
echo 'upgrade_pgTap=PASS'
echo 'upgrade_types=PASS'
echo 'phase12-migration-upgrade=PASS'
