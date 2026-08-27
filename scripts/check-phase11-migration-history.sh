#!/usr/bin/env bash
set -euo pipefail

ORIGINAL_COMMIT="${PHASE11_ORIGINAL_COMMIT:-259e6e58ea9177bda7232281b8951a1c6cf0c78c}"
EXPECTED_BLOB="${PHASE11_ORIGINAL_BLOB:-27664c487a6757e8695bea28bf56f8f60ca338bb}"
BASELINE_F10="${PHASE11_BASELINE_F10:-ee687bb0fefdb5d6899b25f3753d5eac77ce3037}"
MIGRATION_03="supabase/migrations/20260827000003_phase_11_failures_notifications.sql"
MIGRATION_04="supabase/migrations/20260827000004_phase_11_failures_notifications_hardening.sql"

if ! git cat-file -e "${ORIGINAL_COMMIT}^{commit}"; then
  echo "Commit original ${ORIGINAL_COMMIT} não está disponível no clone Git." >&2
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

expected_blob="$(git rev-parse "${ORIGINAL_COMMIT}:${MIGRATION_03}")"
current_blob="$(git hash-object "${MIGRATION_03}")"
if [[ "${expected_blob}" != "${EXPECTED_BLOB}" ]]; then
  echo "O blob esperado da 00003 no commit original divergiu: ${expected_blob}." >&2
  exit 1
fi
if [[ "${current_blob}" != "${EXPECTED_BLOB}" ]]; then
  echo "A migration 00003 não é byte a byte igual à versão publicada: ${current_blob}." >&2
  git diff --no-ext-diff -- "${ORIGINAL_COMMIT}" -- "${MIGRATION_03}" >&2 || true
  exit 1
fi
if ! git diff --exit-code "${ORIGINAL_COMMIT}" -- "${MIGRATION_03}" >/dev/null; then
  echo "A migration 00003 diverge do commit da primeira publicação." >&2
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
  "TG_TABLE_NAME" \
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

sha256="$(sha256sum "${MIGRATION_03}" | cut -d' ' -f1)"
echo "phase11-migration-history=PASS"
echo "migration_00003=identical_to_${ORIGINAL_COMMIT}"
echo "migration_00003_blob=${current_blob}"
echo "migration_00003_sha256=${sha256}"
echo "migration_00004=incremental_hardening"
echo "prior_migrations=unchanged"
