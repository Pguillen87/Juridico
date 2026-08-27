#!/usr/bin/env bash
set -euo pipefail

# Teste de integração real: cada docker exec usa uma conexão PostgreSQL independente.
# Todos os dados são sintéticos; nenhum endpoint ou provider externo é chamado.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

DB_CONTAINER="${SUPABASE_DB_CONTAINER:-$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1 || true)}"
if [[ -z "${DB_CONTAINER}" ]] || ! docker inspect "${DB_CONTAINER}" >/dev/null 2>&1; then
  echo "Não foi possível localizar o container PostgreSQL local do Supabase." >&2
  exit 1
fi

psql_cmd() {
  docker exec -i "${DB_CONTAINER}" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

new_uuid() {
  local hex
  hex="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s-%s-%s-%s-%s\n' \
    "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

OFFICE_ID="$(new_uuid)"
USER_ID="$(new_uuid)"
PARTY_ID="$(new_uuid)"
CLIENT_ID="$(new_uuid)"
PROCESS_ID="$(new_uuid)"
JOB1_ID="$(new_uuid)"
JOB2_ID="$(new_uuid)"
EXEC1_ID="$(new_uuid)"
EXEC2_ID="$(new_uuid)"
EXCHANGE1_ID="$(new_uuid)"
EXCHANGE2_ID="$(new_uuid)"
SNAPSHOT1_ID="$(new_uuid)"
SNAPSHOT2_ID="$(new_uuid)"
EMAIL="phase10-concurrency-${USER_ID}@synthetic.test"
PROCESS_REF="10000000000000000002"
DATA1='{"processRef":"'"${PROCESS_REF}"'","tribunal":"TJ-SYNTHETIC","system":"synthetic-system","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento inicial","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}'
DATA2='{"processRef":"'"${PROCESS_REF}"'","tribunal":"TJ-SYNTHETIC","system":"synthetic-system","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento atualizado","missingFields":[]},{"movementRef":"M-2","date":"2026-01-02T00:00:00Z","description":"Movimento adicionado","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}'

psql_cmd <<SQL
INSERT INTO auth.users (id, email) VALUES ('${USER_ID}', '${EMAIL}');
INSERT INTO public.office (id, name, is_active) VALUES ('${OFFICE_ID}', 'Fase 10 Concorrente Sintético', true);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES ('${USER_ID}', '${OFFICE_ID}', 'Fase 10 Comparator Worker', 'lawyer', false, true);
INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES ('${PARTY_ID}', '${OFFICE_ID}', 'person', 'Fase 10 Party', 'fase 10 party', '${USER_ID}');
INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES ('${CLIENT_ID}', '${OFFICE_ID}', '${PARTY_ID}', 'active', '${USER_ID}');
INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
) VALUES (
  '${PROCESS_ID}', '${OFFICE_ID}', '${CLIENT_ID}', '${PROCESS_REF}',
  'TJ-SYNTHETIC', 'synthetic-system', true, 'active', 'active', '${USER_ID}'
);
INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at, finished_at
) VALUES
('${JOB1_ID}', '${OFFICE_ID}', '${PROCESS_ID}', 'datajud_sandbox', 'process_observation',
 'scheduled', '2026-08-26 11:00:00+00', 'f10-concurrent-job-1', repeat('a',64), 'f10-concurrent-exec-1', 'succeeded', 1, 3, now(), now()),
('${JOB2_ID}', '${OFFICE_ID}', '${PROCESS_ID}', 'datajud_sandbox', 'process_observation',
 'scheduled', '2026-08-26 11:01:00+00', 'f10-concurrent-job-2', repeat('b',64), 'f10-concurrent-exec-2', 'succeeded', 1, 3, now(), now());
INSERT INTO public.provider_exchange (
  id, office_id, process_id, provider_id, source, contract_version,
  subject_ref, correlation_id, request_fingerprint, result_kind, result_status, normalized_result
) VALUES
('${EXCHANGE1_ID}', '${OFFICE_ID}', '${PROCESS_ID}', 'datajud_sandbox', 'datajud', 1, '${PROCESS_REF}', 'f10-concurrent-exec-1', repeat('a',64), 'observation', 'observed', '{}'),
('${EXCHANGE2_ID}', '${OFFICE_ID}', '${PROCESS_ID}', 'datajud_sandbox', 'datajud', 1, '${PROCESS_REF}', 'f10-concurrent-exec-2', repeat('b',64), 'observation', 'observed', '{}');
INSERT INTO public.query_execution (
  id, office_id, query_job_id, process_id, provider_id, capability, attempt_number,
  status, started_at, finished_at, duration_ms, provider_exchange_id, correlation_id
) VALUES
('${EXEC1_ID}', '${OFFICE_ID}', '${JOB1_ID}', '${PROCESS_ID}', 'datajud_sandbox', 'process_observation', 1,
 'succeeded', '2026-08-26 11:00:00+00', '2026-08-26 11:00:01+00', 10, '${EXCHANGE1_ID}', 'f10-concurrent-exec-1'),
('${EXEC2_ID}', '${OFFICE_ID}', '${JOB2_ID}', '${PROCESS_ID}', 'datajud_sandbox', 'process_observation', 1,
 'succeeded', '2026-08-26 11:01:00+00', '2026-08-26 11:01:01+00', 10, '${EXCHANGE2_ID}', 'f10-concurrent-exec-2');
INSERT INTO public.process_snapshot (
  id, office_id, process_id, query_execution_id, provider_id, source, normalizer_version,
  normalized_data, missing_fields, snapshot_hash, created_at
) VALUES
('${SNAPSHOT1_ID}', '${OFFICE_ID}', '${PROCESS_ID}', '${EXEC1_ID}', 'datajud_sandbox', 'datajud', '1.0.0',
 '${DATA1}'::jsonb, '[]'::jsonb,
 encode(extensions.digest(convert_to('${DATA1}'::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
 '2026-08-26 11:00:00+00'),
('${SNAPSHOT2_ID}', '${OFFICE_ID}', '${PROCESS_ID}', '${EXEC2_ID}', 'datajud_sandbox', 'datajud', '1.0.0',
 '${DATA2}'::jsonb, '[]'::jsonb,
 encode(extensions.digest(convert_to('${DATA2}'::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
 '2026-08-26 11:01:00+00');
SQL

psql_cmd <<SQL >/dev/null
SELECT * FROM public.phase10_compare_process_snapshot_v2(
  '${SNAPSHOT1_ID}', 'comparison-v1', 'not_comparable', 'first_snapshot', '[]', '{"entries":[]}'
);
SQL

cat >"${TMP_DIR}/compare-a.sql" <<SQL
BEGIN;
SELECT * FROM public.phase10_compare_process_snapshot_v2(
  '${SNAPSHOT2_ID}', 'comparison-v1', 'changed', NULL,
  '["/system", "/movements/by-ref/M-1/description", "/movements/by-ref/M-2"]',
  '{"entries":[
    {"path":"/system","changeType":"field_updated","before":"synthetic-system","after":"synthetic-system"},
    {"path":"/movements/by-ref/M-1/description","changeType":"movement_updated","before":"Movimento inicial","after":"Movimento atualizado"},
    {"path":"/movements/by-ref/M-2","changeType":"movement_added","after":{"movementRef":"M-2"}}
  ]}'
);
SELECT pg_sleep(1);
COMMIT;
SQL
cp "${TMP_DIR}/compare-a.sql" "${TMP_DIR}/compare-b.sql"

psql_cmd <"${TMP_DIR}/compare-a.sql" >"${TMP_DIR}/compare-a.out" &
PID_A=$!
sleep 0.1
psql_cmd <"${TMP_DIR}/compare-b.sql" >"${TMP_DIR}/compare-b.out" &
PID_B=$!
wait "${PID_A}"
wait "${PID_B}"

RESULT_LINES="$(cat "${TMP_DIR}/compare-a.out" "${TMP_DIR}/compare-b.out" | awk 'NF' | wc -l | tr -d ' ')"
REPLAY_LINES="$(cat "${TMP_DIR}/compare-a.out" "${TMP_DIR}/compare-b.out" | awk -F'|' '$8 == "t" {count += 1} END {print count + 0}')"
if [[ "${RESULT_LINES}" -ne 2 || "${REPLAY_LINES}" -ne 1 ]]; then
  echo "Comparação concorrente inesperada: linhas=${RESULT_LINES} replays=${REPLAY_LINES}" >&2
  cat "${TMP_DIR}/compare-a.out" "${TMP_DIR}/compare-b.out" >&2
  exit 1
fi

VERSION_RC=0
set +e
psql_cmd -c "SELECT * FROM public.phase10_compare_process_snapshot_v2('${SNAPSHOT2_ID}', 'custom', 'changed', NULL, '[\"/system\"]', '{\"entries\":[]}' );" >/dev/null
VERSION_RC=$?
set -e
if [[ "${VERSION_RC}" -eq 0 ]]; then
  echo "Versão não allowlisted foi aceita." >&2
  exit 1
fi

COMPARISON_COUNT="$(psql_cmd -c "SELECT count(*) FROM public.process_comparison WHERE office_id = '${OFFICE_ID}' AND process_id = '${PROCESS_ID}';")"
CHANGE_COUNT="$(psql_cmd -c "SELECT count(*) FROM public.detected_change WHERE office_id = '${OFFICE_ID}' AND process_id = '${PROCESS_ID}';")"
DIFF_COLUMNS="$(psql_cmd -c "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'detected_change' AND column_name IN ('changed_fields', 'normalized_diff');")"
if [[ "${COMPARISON_COUNT}" -ne 2 || "${CHANGE_COUNT}" -ne 1 || "${DIFF_COLUMNS}" -ne 0 ]]; then
  echo "Persistência comparativa inesperada: comparisons=${COMPARISON_COUNT} changes=${CHANGE_COUNT} diff_columns=${DIFF_COLUMNS}" >&2
  exit 1
fi

printf '%s\n' \
  "phase10-comparison-concurrency=PASS" \
  "concurrent_comparison_results=${RESULT_LINES}" \
  "concurrent_replays=${REPLAY_LINES}" \
  "process_comparisons=${COMPARISON_COUNT}" \
  "detected_changes=${CHANGE_COUNT}" \
  "detected_change_diff_columns=${DIFF_COLUMNS}" \
  "unknown_version_rejected=1"
