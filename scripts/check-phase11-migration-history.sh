#!/usr/bin/env bash
set -euo pipefail

DEFECTIVE_COMMIT="${PHASE11_DEFECTIVE_COMMIT:-259e6e58ea9177bda7232281b8951a1c6cf0c78c}"
DEFECTIVE_BLOB="${PHASE11_DEFECTIVE_BLOB:-27664c487a6757e8695bea28bf56f8f60ca338bb}"
CANONICAL_BLOB="${PHASE11_CANONICAL_BLOB:-8d4d9cbcf030d288a5d91ff8262241de94a9bd8c}"
CANONICAL_SHA256="${PHASE11_CANONICAL_SHA256:-3c61a4215c084d452d70f58ee28a7837df076a5f7716de3ebe774b4bfb200775}"
HARDENING_COMMIT="${PHASE11_HARDENING_COMMIT:-5694baecccdaa0cf116156d6418f2107bdfc259f}"
BASELINE_F10="${PHASE11_BASELINE_F10:-ee687bb0fefdb5d6899b25f3753d5eac77ce3037}"
MIGRATION_03="supabase/migrations/20260827000003_phase_11_failures_notifications.sql"
MIGRATION_04="supabase/migrations/20260827000004_phase_11_failures_notifications_hardening.sql"

if ! git cat-file -e "${DEFECTIVE_COMMIT}^{commit}"; then
  echo "Commit da primeira publicação ${DEFECTIVE_COMMIT} não está disponível no clone Git." >&2
  exit 1
fi

if ! git cat-file -e "${HARDENING_COMMIT}^{commit}"; then
  echo "Commit de publicação da 00004 ${HARDENING_COMMIT} não está disponível no clone Git." >&2
  exit 1
fi

if ! git cat-file -e "${BASELINE_F10}^{commit}"; then
  echo "Baseline Fase 10 ${BASELINE_F10} não está disponível no clone Git." >&2
  exit 1
fi

if [[ ! -f "${MIGRATION_03}" || ! -f "${MIGRATION_04}" ]]; then
  echo "As migrations 00003 e 00004 da Fase 11 devem existir." >&2
  exit 1
fi

defective_blob="$(git rev-parse "${DEFECTIVE_COMMIT}:${MIGRATION_03}")"
current_blob="$(git hash-object "${MIGRATION_03}")"
hardening_published_blob="$(git rev-parse "${HARDENING_COMMIT}:${MIGRATION_04}")"
current_hardening_blob="$(git hash-object "${MIGRATION_04}")"
if [[ "${defective_blob}" != "${DEFECTIVE_BLOB}" ]]; then
  echo "O blob histórico defeituoso esperado divergiu: ${defective_blob}." >&2
  exit 1
fi
if [[ "${current_blob}" != "${CANONICAL_BLOB}" ]]; then
  echo "A migration 00003 não corresponde ao novo blob canônico: ${current_blob}." >&2
  git diff --no-ext-diff -- "${DEFECTIVE_COMMIT}" -- "${MIGRATION_03}" >&2 || true
  exit 1
fi
if [[ "${current_blob}" == "${DEFECTIVE_BLOB}" ]]; then
  echo "A migration 00003 continua no blob histórico defeituoso." >&2
  exit 1
fi
if [[ "${current_hardening_blob}" != "${hardening_published_blob}" ]]; then
  echo "A migration 00004 diverge da primeira publicação do hardening." >&2
  exit 1
fi

exception_diff="$(git diff --no-ext-diff --unified=0 "${DEFECTIVE_COMMIT}" -- "${MIGRATION_03}")"
exception_counts="$(git diff --numstat "${DEFECTIVE_COMMIT}" -- "${MIGRATION_03}" | awk '{print $1 ":" $2}')"
tg_table_name_count="$(grep -Fc 'TG_TABLE_NAME' "${MIGRATION_03}" || true)"
if [[ "${exception_counts}" != "4:2" || "${tg_table_name_count}" != "2" ]]; then
  echo "O diff da exceção não contém somente os dois argumentos TG_TABLE_NAME esperados." >&2
  printf '%s\n' "${exception_diff}" >&2
  exit 1
fi

canonical_sha256="$(sha256sum "${MIGRATION_03}" | cut -d' ' -f1)"
if [[ "${canonical_sha256}" != "${CANONICAL_SHA256}" ]]; then
  echo "O SHA-256 da migration 00003 divergiu: ${canonical_sha256}." >&2
  exit 1
fi

if [[ "$(head -n 1 "${MIGRATION_04}")" != "SET lock_timeout = '2s';" ]]; then
  echo "A migration 00004 não começa com SET lock_timeout = '2s';" >&2
  exit 1
fi

for required in \
  "CREATE OR REPLACE FUNCTION public.phase11_block_append_only_mutation()" \
  "CREATE OR REPLACE FUNCTION public.phase11_record_failure_event_internal(" \
  "CREATE OR REPLACE FUNCTION public.phase11_request_failure_reprocess(" \
  "IF current_user NOT IN ('service_role', 'postgres')" \
  "SELECT fo.query_job_id INTO new_job_id" \
  "GRANT EXECUTE ON FUNCTION public.phase11_record_failure_event_internal(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID, UUID, UUID, INTEGER, TEXT, TEXT) TO service_role;"; do
  if ! grep -Fq "${required}" "${MIGRATION_04}"; then
    echo "Hardening esperado ausente na migration 00004: ${required}" >&2
    exit 1
  fi
done

for post_publication_change in \
  "IF current_user NOT IN ('service_role', 'postgres')" \
  "SELECT fo.query_job_id INTO new_job_id" \
  "GRANT EXECUTE ON FUNCTION public.phase11_record_failure_event_internal(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID, UUID, UUID, INTEGER, TEXT, TEXT) TO service_role;"; do
  if grep -Fq "${post_publication_change}" "${MIGRATION_03}"; then
    echo "Hardening pós-publicação vazou para a migration histórica 00003: ${post_publication_change}" >&2
    exit 1
  fi
done

if grep -Eq '^[[:space:]]*(DROP[[:space:]]+TABLE|DROP[[:space:]]+TYPE|TRUNCATE[[:space:]])' "${MIGRATION_04}"; then
  echo "A migration 00004 contém DDL destrutivo não permitido." >&2
  exit 1
fi

for prior_migration in \
  supabase/migrations/20260826000011_phase_9_scheduler_queue_snapshots.sql \
  supabase/migrations/20260826000012_phase_9_stale_lease_hardening.sql \
  supabase/migrations/20260827000001_phase_10_comparison_detection.sql \
  supabase/migrations/20260827000002_phase_10_comparison_hardening.sql; do
  if ! git diff --quiet "${BASELINE_F10}" -- "${prior_migration}"; then
    echo "Migration anterior foi alterada indevidamente: ${prior_migration}" >&2
    exit 1
  fi
done

echo "phase11-migration-history=PASS"
echo "migration_00003=canonical_after_authorized_exception"
echo "migration_00003_defective_blob=${DEFECTIVE_BLOB}"
echo "migration_00003_canonical_blob=${current_blob}"
echo "migration_00003_canonical_sha256=${canonical_sha256}"
echo "exception_scope=two_TG_TABLE_NAME_arguments_only"
echo "migration_00004=immutable_incremental_hardening"
echo "migration_00004_blob=${current_hardening_blob}"
echo "prior_migrations=unchanged"
