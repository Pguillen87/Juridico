#!/usr/bin/env bash
set -euo pipefail

BASE_SHA="${PHASE10_ORIGINAL_SHA:-7527d6a9e77b4583d779b8197bbc1fe5eac5d78a}"
MIGRATION_01="supabase/migrations/20260827000001_phase_10_comparison_detection.sql"
MIGRATION_02="supabase/migrations/20260827000002_phase_10_comparison_hardening.sql"

if ! git cat-file -e "${BASE_SHA}^{commit}"; then
  echo "Commit original ${BASE_SHA} não está disponível no clone Git." >&2
  exit 1
fi

if ! git diff --quiet "${BASE_SHA}" -- "${MIGRATION_01}"; then
  echo "A migration 00001 diverge do conteúdo publicado em ${BASE_SHA}." >&2
  git diff -- "${BASE_SHA}" -- "${MIGRATION_01}" >&2 || true
  exit 1
fi

if [[ -z "$(git status --porcelain -- "${MIGRATION_01}")" ]]; then
  git diff --exit-code "${BASE_SHA}...HEAD" -- "${MIGRATION_01}"
fi

if [[ "$(head -n 1 "${MIGRATION_02}")" != "SET lock_timeout = '2s';" ]]; then
  echo "A migration 00002 não começa com SET lock_timeout = '2s';" >&2
  exit 1
fi

for required in \
  "phase10_resolve_compatible_previous_snapshot" \
  "phase10_get_snapshot_pair_compatible_internal" \
  "phase10_compare_process_snapshot_v2"; do
  if ! grep -q "${required}" "${MIGRATION_02}"; then
    echo "O hardening esperado (${required}) não está na migration 00002." >&2
    exit 1
  fi
done

for prohibited in \
  "phase10_resolve_compatible_previous_snapshot" \
  "phase10_get_snapshot_pair_compatible_internal" \
  "phase10_compare_process_snapshot_v2"; do
  if grep -q "${prohibited}" "${MIGRATION_01}"; then
    echo "O hardening (${prohibited}) foi introduzido indevidamente na migration 00001." >&2
    exit 1
  fi
done

echo "phase10-migration-history=PASS"
echo "migration_00001=identical_to_${BASE_SHA}"
echo "comparison_hardening=exclusive_in_00002"
