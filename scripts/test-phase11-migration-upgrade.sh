#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI=(npx --no-install supabase)
PRETTIER=(npx --no-install prettier)
TMP_DIR="$(mktemp -d)"
F10_PROJECT_DIR="${TMP_DIR}/phase10-project"
PRE_HARDENING_PROJECT_DIR="${TMP_DIR}/phase11-pre-hardening-project"
FINGERPRINT_SQL="${TMP_DIR}/schema-fingerprint.sql"
MIGRATIONS_SQL="${TMP_DIR}/migration-versions.sql"
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
    WHERE n.nspname = 'public' AND p.proname LIKE 'phase11_%'
  ), ''),
  coalesce((
    SELECT string_agg(
      grantee || '|' || routine_schema || '|' || routine_name || '|' || privilege_type || '|' || is_grantable,
      E'\n'
      ORDER BY grantee, routine_schema, routine_name, privilege_type
    )
    FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public' AND routine_name LIKE 'phase11_%'
  ), ''),
  coalesce((
    SELECT string_agg(
      table_schema || '.' || table_name || '|' || column_name || '|' || ordinal_position::text || '|' || data_type || '|' || is_nullable || '|' || coalesce(column_default, ''),
      E'\n'
      ORDER BY table_schema, table_name, ordinal_position
    )
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name IN ('failure_incident', 'failure_occurrence', 'notification_outbox')
  ), ''),
  coalesce((
    SELECT string_agg(
      n.nspname || '.' || c.relname || '|' || c.relkind::text,
      E'\n'
      ORDER BY n.nspname, c.relname
    )
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('failure_incident', 'failure_occurrence', 'notification_outbox')
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
      AND c.relname IN ('failure_incident', 'failure_occurrence', 'notification_outbox')
  ), ''),
  coalesce((
    SELECT string_agg(
      schemaname || '.' || tablename || '|' || indexname || '|' || indexdef,
      E'\n'
      ORDER BY schemaname, tablename, indexname
    )
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename IN ('failure_incident', 'failure_occurrence', 'notification_outbox')
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
      AND c.relname IN ('failure_incident', 'failure_occurrence', 'notification_outbox')
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
      AND c.relname IN ('failure_incident', 'failure_occurrence', 'notification_outbox')
  ), ''),
  coalesce((
    SELECT string_agg(version, E'\n' ORDER BY version)
    FROM supabase_migrations.schema_migrations
    WHERE version IN ('20260827000003', '20260827000004')
  ), '')
)) AS fingerprint;
SQL

cat >"${MIGRATIONS_SQL}" <<'SQL'
SELECT version
FROM supabase_migrations.schema_migrations
WHERE version IN ('20260827000003', '20260827000004')
ORDER BY version;
SQL

run_supabase() {
  "${CLI[@]}" "$@"
}

fingerprint() {
  local workdir="$1"
  local output="${TMP_DIR}/fingerprint-$(basename "${workdir}").txt"
  run_supabase db query --local --workdir "${workdir}" --file "${FINGERPRINT_SQL}" >"${output}"
  local value
  value="$(grep -Eo '[0-9a-f]{32}' "${output}" | tail -1 || true)"
  if [[ ! "${value}" =~ ^[0-9a-f]{32}$ ]]; then
    echo "Não foi possível obter fingerprint de schema em ${workdir}." >&2
    cat "${output}" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

generate_types() {
  local workdir="$1"
  local output="$2"
  run_supabase gen types typescript --local --workdir "${workdir}" >"${output}"
  "${PRETTIER[@]}" --write "${output}" >/dev/null
}

dump_schema() {
  local workdir="$1"
  local output="$2"
  run_supabase db dump --local --schema public --workdir "${workdir}" --file "${output}" >/dev/null
}

migration_versions() {
  local workdir="$1"
  run_supabase db query --local --workdir "${workdir}" --file "${MIGRATIONS_SQL}"
}

echo 'phase11-upgrade=full-reset'
run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null
full_fingerprint="$(fingerprint "${ROOT_DIR}")"
generate_types "${ROOT_DIR}" "${TMP_DIR}/full-types.ts"
dump_schema "${ROOT_DIR}" "${TMP_DIR}/full-schema.sql"
if ! run_supabase test db --local --workdir "${ROOT_DIR}" >"${TMP_DIR}/phase11-full-pgtap.log" 2>&1; then
  echo 'Falha no pgTAP do reset completo Fase 11→00004.' >&2
  tail -240 "${TMP_DIR}/phase11-full-pgtap.log" >&2
  exit 1
fi
echo "full_reset_fingerprint=${full_fingerprint}"
echo 'full_reset_pgTap=PASS'

echo 'phase11-upgrade=prepare-phase10-schema'
mkdir -p "${F10_PROJECT_DIR}"
cp -R "${ROOT_DIR}/supabase" "${F10_PROJECT_DIR}/supabase"
rm -f "${F10_PROJECT_DIR}/supabase/migrations/20260827000003_phase_11_failures_notifications.sql"
rm -f "${F10_PROJECT_DIR}/supabase/migrations/20260827000004_phase_11_failures_notifications_hardening.sql"
run_supabase db reset --local --workdir "${F10_PROJECT_DIR}" --yes >/dev/null

echo 'phase11-upgrade=apply-canonical-00003'
mkdir -p "${PRE_HARDENING_PROJECT_DIR}"
cp -R "${F10_PROJECT_DIR}/supabase" "${PRE_HARDENING_PROJECT_DIR}/supabase"
cp "${ROOT_DIR}/supabase/migrations/20260827000003_phase_11_failures_notifications.sql" \
  "${PRE_HARDENING_PROJECT_DIR}/supabase/migrations/20260827000003_phase_11_failures_notifications.sql"
run_supabase db push --local --workdir "${PRE_HARDENING_PROJECT_DIR}" --yes >/dev/null
pre_hardening_versions="$(migration_versions "${PRE_HARDENING_PROJECT_DIR}")"
if ! grep -Fq '20260827000003' <<<"${pre_hardening_versions}" \
  || grep -Fq '20260827000004' <<<"${pre_hardening_versions}"; then
  echo 'O estado pré-hardening não contém exatamente a 00003 corrigida sem a 00004.' >&2
  printf '%s\n' "${pre_hardening_versions}" >&2
  exit 1
fi
pre_hardening_fingerprint="$(fingerprint "${PRE_HARDENING_PROJECT_DIR}")"
echo "pre_hardening_00003_fingerprint=${pre_hardening_fingerprint}"
echo 'pre_hardening_schema=PASS'

echo 'phase11-upgrade=apply-incremental-00004'
run_supabase db push --local --workdir "${ROOT_DIR}" --yes >/dev/null
upgrade_fingerprint="$(fingerprint "${ROOT_DIR}")"
generate_types "${ROOT_DIR}" "${TMP_DIR}/upgrade-types.ts"
dump_schema "${ROOT_DIR}" "${TMP_DIR}/upgrade-schema.sql"
if ! run_supabase test db --local --workdir "${ROOT_DIR}" >"${TMP_DIR}/phase11-upgrade-pgtap.log" 2>&1; then
  echo 'Falha no pgTAP do upgrade incremental Fase 10→00003→00004.' >&2
  tail -240 "${TMP_DIR}/phase11-upgrade-pgtap.log" >&2
  exit 1
fi
run_supabase db reset --local --workdir "${ROOT_DIR}" --yes >/dev/null

echo 'post_upgrade_clean_reset=PASS'

if [[ "${full_fingerprint}" != "${upgrade_fingerprint}" ]]; then
  echo "Fingerprint do reset completo diverge do upgrade Fase 10→00003→00004: ${full_fingerprint} != ${upgrade_fingerprint}." >&2
  diff -u "${TMP_DIR}/full-schema.sql" "${TMP_DIR}/upgrade-schema.sql" | head -240 >&2 || true
  exit 1
fi
if ! cmp -s "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts"; then
  echo 'Tipos gerados divergem entre reset completo e upgrade Fase 10→00003→00004.' >&2
  diff -u "${TMP_DIR}/full-types.ts" "${TMP_DIR}/upgrade-types.ts" >&2 || true
  exit 1
fi

echo "upgrade_fingerprint=${upgrade_fingerprint}"
echo 'upgrade_pgTap=PASS'
echo 'upgrade_types=PASS'
echo 'phase11-migration-upgrade=PASS'
