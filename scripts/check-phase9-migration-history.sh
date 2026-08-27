#!/usr/bin/env bash
set -euo pipefail

BASE_SHA="${PHASE9_BASE_SHA:-2904185d0e43546e6f48433533326878fb200c80}"
MIGRATION_11="supabase/migrations/20260826000011_phase_9_scheduler_queue_snapshots.sql"
MIGRATION_12="supabase/migrations/20260826000012_phase_9_stale_lease_hardening.sql"

if ! git cat-file -e "${BASE_SHA}^{commit}"; then
  echo "Baseline ${BASE_SHA} não está disponível no clone Git." >&2
  exit 1
fi

if ! git diff --quiet "${BASE_SHA}" -- "${MIGRATION_11}"; then
  echo "A migration 00011 diverge da versão publicada na baseline ${BASE_SHA}." >&2
  git diff -- "${BASE_SHA}" -- "${MIGRATION_11}" >&2 || true
  exit 1
fi

# Em checkout limpo, prova também a forma histórica exigida pelo corretivo.
if [[ -z "$(git status --porcelain -- "${MIGRATION_11}")" ]]; then
  git diff --exit-code "${BASE_SHA}...HEAD" -- "${MIGRATION_11}"
fi

if [[ "$(head -n 1 "${MIGRATION_12}")" != "SET lock_timeout = '2s';" ]]; then
  echo "A migration 00012 não começa com SET lock_timeout = '2s';" >&2
  exit 1
fi

if ! grep -q "CREATE OR REPLACE FUNCTION public.phase9_complete_query_execution(" "${MIGRATION_12}"; then
  echo "A migration 00012 não reaplica a função de conclusão esperada." >&2
  exit 1
fi

if ! grep -q "query execution lease is no longer active" "${MIGRATION_12}"; then
  echo "O hardening de execution stale não está na migration 00012." >&2
  exit 1
fi

if grep -q "query execution lease is no longer active" "${MIGRATION_11}"; then
  echo "O hardening stale permanece indevidamente dentro da migration 00011." >&2
  exit 1
fi

if grep -Eq 'CREATE TABLE|ALTER TABLE|DROP[[:space:]]|CREATE[[:space:]]+(UNIQUE[[:space:]]+)?INDEX|GRANT[[:space:]]|REVOKE[[:space:]]' "${MIGRATION_12}"; then
  echo "A migration 00012 contém DDL/grants fora do hardening localizado." >&2
  exit 1
fi

echo "phase9-migration-history=PASS"
echo "migration_00011=identical_to_${BASE_SHA}"
echo "stale_lease_hardening=exclusive_in_00012"
