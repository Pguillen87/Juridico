#!/usr/bin/env bash
set -euo pipefail

# Teste de integração real: cada docker exec inicia um psql independente.
# Todos os dados são sintéticos e o teste deve rodar depois do db reset/pgTAP.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
BASE_SHA="${PHASE9_BASE_SHA:-2904185d0e43546e6f48433533326878fb200c80}"
MIGRATION_11="supabase/migrations/20260826000011_phase_9_scheduler_queue_snapshots.sql"
MIGRATION_12="supabase/migrations/20260826000012_phase_9_stale_lease_hardening.sql"

# Integridade histórica obrigatória: 00011 publicada é imutável; o guard vive em 00012.
cd "${REPO_ROOT}"
git cat-file -e "${BASE_SHA}^{commit}"
git diff --exit-code "${BASE_SHA}" -- "${MIGRATION_11}"
if [[ -z "$(git status --porcelain -- "${MIGRATION_11}")" ]]; then
  git diff --exit-code "${BASE_SHA}...HEAD" -- "${MIGRATION_11}"
fi
if grep -q "query execution lease is no longer active" "${MIGRATION_11}"; then
  echo "O stale guard não pode existir na migration publicada 00011." >&2
  exit 1
fi
if ! grep -q "query execution lease is no longer active" "${MIGRATION_12}"; then
  echo "O stale guard deve existir na migration incremental 00012." >&2
  exit 1
fi

echo "migration-history=PASS (00011 idêntica à baseline; guard exclusivo em 00012)"

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
JOB2_ID="$(new_uuid)"
EMAIL="phase9-concurrency-${USER_ID}@synthetic.test"
CNJ="91000000000000000011"

psql_cmd <<SQL
INSERT INTO auth.users (id, email)
VALUES ('${USER_ID}', '${EMAIL}');
INSERT INTO public.office (id, name, is_active)
VALUES ('${OFFICE_ID}', 'Fase 9 Concurrente Sintético', true);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES ('${USER_ID}', '${OFFICE_ID}', 'Fase 9 Worker Test', 'lawyer', false, true);
INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES ('${PARTY_ID}', '${OFFICE_ID}', 'person', 'Parte Sintética Fase 9', 'parte sintética fase 9', '${USER_ID}');
INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES ('${CLIENT_ID}', '${OFFICE_ID}', '${PARTY_ID}', 'active', '${USER_ID}');
INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
)
VALUES (
  '${PROCESS_ID}', '${OFFICE_ID}', '${CLIENT_ID}', '${CNJ}', 'TJ-SYNTHETIC',
  'synthetic-system', true, 'paused', 'active', '${USER_ID}'
);
SQL

CONFIG_ID="$(psql_cmd -c "SELECT public.phase9_upsert_monitoring_configuration('${OFFICE_ID}', 'America/Sao_Paulo', true, 1);")"
psql_cmd -c "SELECT public.phase9_upsert_monitoring_schedule('${CONFIG_ID}', '10:00:00', 'America/Sao_Paulo', ARRAY[1,2,3,4,5,6,7], true);" >/dev/null

psql_cmd <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '${USER_ID}', false);
SELECT public.phase9_set_process_monitoring_status('${PROCESS_ID}', 'active');
RESET ROLE;
SQL

# 1) Dois ticks concorrentes para a mesma janela lógica: somente um deve criar job.
cat >"${TMP_DIR}/scheduler-a.sql" <<SQL
BEGIN;
SELECT public.phase9_scheduler_tick('2026-08-26 13:02:00+00', 300);
SELECT pg_sleep(1);
COMMIT;
SQL
cp "${TMP_DIR}/scheduler-a.sql" "${TMP_DIR}/scheduler-b.sql"

psql_cmd <"${TMP_DIR}/scheduler-a.sql" >"${TMP_DIR}/scheduler-a.out" &
SCHEDULER_A_PID=$!
sleep 0.1
psql_cmd <"${TMP_DIR}/scheduler-b.sql" >"${TMP_DIR}/scheduler-b.out" &
SCHEDULER_B_PID=$!
set +e
wait "${SCHEDULER_A_PID}"
SCHEDULER_A_RC=$?
wait "${SCHEDULER_B_PID}"
SCHEDULER_B_RC=$?
set -e
if [[ "${SCHEDULER_A_RC}" -ne 0 || "${SCHEDULER_B_RC}" -ne 0 ]]; then
  echo "Falha no scheduler concorrente: rc_a=${SCHEDULER_A_RC} rc_b=${SCHEDULER_B_RC}" >&2
  exit 1
fi
SCHEDULER_CREATED="$(cat "${TMP_DIR}/scheduler-a.out" "${TMP_DIR}/scheduler-b.out" | awk 'NF' | awk '{sum += $1} END {print sum + 0}')"
JOB_COUNT="$(psql_cmd -c "SELECT count(*) FROM public.query_job WHERE office_id = '${OFFICE_ID}' AND process_id = '${PROCESS_ID}' AND job_kind = 'scheduled';")"
if [[ "${SCHEDULER_CREATED}" -ne 1 || "${JOB_COUNT}" -ne 1 ]]; then
  echo "Falha na idempotência do scheduler: retornos=${SCHEDULER_CREATED} jobs=${JOB_COUNT}" >&2
  exit 1
fi
JOB_ID="$(psql_cmd -c "SELECT id FROM public.query_job WHERE office_id = '${OFFICE_ID}' AND process_id = '${PROCESS_ID}' AND job_kind = 'scheduled';")"

# 2) Dois workers concorrentes no mesmo job: somente um claim recebe lease.
cat >"${TMP_DIR}/claim-a.sql" <<SQL
BEGIN;
SELECT * FROM public.phase9_claim_query_job('phase9-worker-a', 60000);
SELECT pg_sleep(1);
COMMIT;
SQL
cp "${TMP_DIR}/claim-a.sql" "${TMP_DIR}/claim-b.sql"
sed -i "s/phase9-worker-a/phase9-worker-b/" "${TMP_DIR}/claim-b.sql"

psql_cmd <"${TMP_DIR}/claim-a.sql" >"${TMP_DIR}/claim-a.out" &
CLAIM_A_PID=$!
sleep 0.1
psql_cmd <"${TMP_DIR}/claim-b.sql" >"${TMP_DIR}/claim-b.out" &
CLAIM_B_PID=$!
set +e
wait "${CLAIM_A_PID}"
CLAIM_A_RC=$?
wait "${CLAIM_B_PID}"
CLAIM_B_RC=$?
set -e
if [[ "${CLAIM_A_RC}" -ne 0 || "${CLAIM_B_RC}" -ne 0 ]]; then
  echo "Falha no claim concorrente: rc_a=${CLAIM_A_RC} rc_b=${CLAIM_B_RC}" >&2
  exit 1
fi
CLAIM_LINES_A="$(awk 'NF' "${TMP_DIR}/claim-a.out" | wc -l | tr -d ' ')"
CLAIM_LINES_B="$(awk 'NF' "${TMP_DIR}/claim-b.out" | wc -l | tr -d ' ')"
if [[ "$((CLAIM_LINES_A + CLAIM_LINES_B))" -ne 1 ]]; then
  echo "Falha no claim exclusivo: linhas_a=${CLAIM_LINES_A} linhas_b=${CLAIM_LINES_B}" >&2
  exit 1
fi
CLAIM_OUT="${TMP_DIR}/claim-a.out"
if [[ "${CLAIM_LINES_A}" -eq 0 ]]; then
  CLAIM_OUT="${TMP_DIR}/claim-b.out"
fi
IFS='|' read -r CLAIM_JOB EXECUTION_ID CLAIM_OFFICE CLAIM_PROCESS PROVIDER_ID CAPABILITY JOB_KIND SUBJECT_REF REQUEST_FINGERPRINT CORRELATION_ID ATTEMPT_NUMBER LEASE_TOKEN LEASE_EXPIRES <"${CLAIM_OUT}"
if [[ "${CLAIM_JOB}" != "${JOB_ID}" || "${CLAIM_PROCESS}" != "${PROCESS_ID}" || "${ATTEMPT_NUMBER}" -ne 1 ]]; then
  echo "Claim retornou dados inesperados: job=${CLAIM_JOB} process=${CLAIM_PROCESS} attempt=${ATTEMPT_NUMBER}" >&2
  exit 1
fi

# Observação válida, usada por ambas as conclusões concorrentes.
OBSERVED_AT="2026-08-26T13:02:10.000Z"
cat >"${TMP_DIR}/complete-a.sql" <<SQL
BEGIN;
SELECT * FROM public.phase9_complete_query_execution(
  '${CLAIM_JOB}'::uuid, '${EXECUTION_ID}'::uuid, '${LEASE_TOKEN}'::uuid,
  'observation', 'observed', NULL,
  jsonb_build_object(
    'kind', 'observation',
    'status', 'observed',
    'provider', jsonb_build_object(
      'providerId', 'datajud_sandbox', 'providerKind', 'datajud',
      'adapterVersion', '1.0.0', 'contractVersion', '1'
    ),
    'source', 'datajud', 'contractVersion', '1',
    'capability', 'process_observation',
    'data', jsonb_build_object(
      'processRef', '${CNJ}', 'tribunal', 'TJ-SYNTHETIC',
      'system', 'synthetic-system', 'movements', '[]'::jsonb, 'parties', '[]'::jsonb
    ),
    'returnedFields', to_jsonb(ARRAY['processRef','tribunal','system','movements','parties']::text[]),
    'missingFields', '[]'::jsonb,
    'sourceMetadata', jsonb_build_object(
      'sourceType', 'datajud', 'providerId', 'datajud_sandbox',
      'adapterVersion', '1.0.0', 'contractVersion', '1',
      'observedAt', '${OBSERVED_AT}', 'durationMs', 10
    ),
    'correlationId', '${CORRELATION_ID}',
    'evidence', jsonb_build_object(
      'evidenceRef', 'datajud-fixture:${CORRELATION_ID}',
      'evidenceType', 'synthetic_fixture', 'observedAt', '${OBSERVED_AT}'
    )
  ),
  jsonb_build_object('outcome', 'observation', 'processRef', '${CNJ}'),
  'phase9-sanitize-v1', '${OBSERVED_AT}'::timestamptz, 200, 10, NULL
);
SELECT pg_sleep(1);
COMMIT;
SQL
cp "${TMP_DIR}/complete-a.sql" "${TMP_DIR}/complete-b.sql"

# 3) Duas conclusões concorrentes para o mesmo execution: a segunda é idempotente;
#    nenhuma segunda exchange/snapshot pode ser criada.
psql_cmd <"${TMP_DIR}/complete-a.sql" >"${TMP_DIR}/complete-a.out" &
COMPLETE_A_PID=$!
sleep 0.1
psql_cmd <"${TMP_DIR}/complete-b.sql" >"${TMP_DIR}/complete-b.out" &
COMPLETE_B_PID=$!
set +e
wait "${COMPLETE_A_PID}"
COMPLETE_A_RC=$?
wait "${COMPLETE_B_PID}"
COMPLETE_B_RC=$?
set -e
if [[ "${COMPLETE_A_RC}" -ne 0 || "${COMPLETE_B_RC}" -ne 0 ]]; then
  echo "Falha na conclusão concorrente: rc_a=${COMPLETE_A_RC} rc_b=${COMPLETE_B_RC}" >&2
  exit 1
fi
SNAPSHOT_COUNT="$(psql_cmd -c "SELECT count(*) FROM public.process_snapshot WHERE query_execution_id = '${EXECUTION_ID}';")"
EXCHANGE_COUNT="$(psql_cmd -c "SELECT count(*) FROM public.provider_exchange WHERE correlation_id = '${CORRELATION_ID}';")"
if [[ "${SNAPSHOT_COUNT}" -ne 1 || "${EXCHANGE_COUNT}" -ne 1 ]]; then
  echo "Conclusão concorrente duplicou dados: snapshots=${SNAPSHOT_COUNT} exchanges=${EXCHANGE_COUNT}" >&2
  exit 1
fi

# 4) Criar um segundo job sintético, obter lease antiga, recuperar, obter nova lease
#    e provar que a conclusão com execution/token antigos é rejeitada.
CORRELATION_2="phase9-stale-${JOB2_ID}"
IDEMPOTENCY_2="scheduled:stale:${JOB2_ID}"
psql_cmd <<SQL
INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at
)
VALUES (
  '${JOB2_ID}', '${OFFICE_ID}', '${PROCESS_ID}', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-26 13:03:00+00',
  '${IDEMPOTENCY_2}', encode(extensions.digest(convert_to('${IDEMPOTENCY_2}', 'UTF8'), 'sha256'), 'hex'),
  '${CORRELATION_2}', 'pending', 0, 3, clock_timestamp()
);
SQL
STALE_CLAIM="$(psql_cmd -c "SELECT * FROM public.phase9_claim_query_job('phase9-worker-stale-old', 60000);")"
IFS='|' read -r STALE_JOB OLD_EXECUTION_ID _STALE_OFFICE _STALE_PROCESS _STALE_PROVIDER _STALE_CAPABILITY _STALE_KIND _STALE_SUBJECT _STALE_FINGERPRINT OLD_CORRELATION _STALE_ATTEMPT OLD_LEASE_TOKEN _STALE_EXPIRES <<<"${STALE_CLAIM}"
psql_cmd <<SQL
SELECT set_config('juridico.phase9_internal', '1', false);
UPDATE public.query_job
   SET lease_expires_at = clock_timestamp() - interval '1 second'
 WHERE id = '${JOB2_ID}';
SELECT public.phase9_recover_expired_query_jobs(10);
SQL
sleep 1.2
NEW_CLAIM="$(psql_cmd -c "SELECT * FROM public.phase9_claim_query_job('phase9-worker-stale-new', 60000);")"
IFS='|' read -r NEW_JOB NEW_EXECUTION_ID _NEW_OFFICE _NEW_PROCESS _NEW_PROVIDER _NEW_CAPABILITY _NEW_KIND _NEW_SUBJECT _NEW_FINGERPRINT NEW_CORRELATION _NEW_ATTEMPT NEW_LEASE_TOKEN _NEW_EXPIRES <<<"${NEW_CLAIM}"
if [[ "${NEW_JOB}" != "${JOB2_ID}" || "${OLD_EXECUTION_ID}" == "${NEW_EXECUTION_ID}" || "${OLD_LEASE_TOKEN}" == "${NEW_LEASE_TOKEN}" ]]; then
  echo "A nova lease não foi criada corretamente: old_exec=${OLD_EXECUTION_ID} new_exec=${NEW_EXECUTION_ID}" >&2
  exit 1
fi

cat >"${TMP_DIR}/stale-complete.sql" <<SQL
SELECT * FROM public.phase9_complete_query_execution(
  '${JOB2_ID}'::uuid, '${OLD_EXECUTION_ID}'::uuid, '${OLD_LEASE_TOKEN}'::uuid,
  'observation', 'observed', NULL,
  jsonb_build_object(
    'kind', 'observation', 'status', 'observed',
    'provider', jsonb_build_object(
      'providerId', 'datajud_sandbox', 'providerKind', 'datajud',
      'adapterVersion', '1.0.0', 'contractVersion', '1'
    ),
    'source', 'datajud', 'contractVersion', '1', 'capability', 'process_observation',
    'data', jsonb_build_object('processRef', '${CNJ}'),
    'returnedFields', to_jsonb(ARRAY['processRef']::text[]), 'missingFields', '[]'::jsonb,
    'sourceMetadata', jsonb_build_object(
      'sourceType', 'datajud', 'providerId', 'datajud_sandbox',
      'adapterVersion', '1.0.0', 'contractVersion', '1',
      'observedAt', '${OBSERVED_AT}', 'durationMs', 10
    ),
    'correlationId', '${OLD_CORRELATION}',
    'evidence', jsonb_build_object(
      'evidenceRef', 'datajud-fixture:${OLD_CORRELATION}',
      'evidenceType', 'synthetic_fixture', 'observedAt', '${OBSERVED_AT}'
    )
  ),
  jsonb_build_object('outcome', 'observation', 'processRef', '${CNJ}'),
  'phase9-sanitize-v1', '${OBSERVED_AT}'::timestamptz, 200, 10, NULL
);
SQL
set +e
psql_cmd <"${TMP_DIR}/stale-complete.sql" >"${TMP_DIR}/stale-complete.out" 2>"${TMP_DIR}/stale-complete.err"
STALE_RC=$?
set -e
if [[ "${STALE_RC}" -eq 0 ]]; then
  echo "Falha: lease antiga conseguiu concluir depois de uma nova lease válida." >&2
  exit 1
fi

# A nova lease permanece válida e deve conseguir concluir uma única vez.
cat >"${TMP_DIR}/new-complete.sql" <<SQL
SELECT * FROM public.phase9_complete_query_execution(
  '${JOB2_ID}'::uuid, '${NEW_EXECUTION_ID}'::uuid, '${NEW_LEASE_TOKEN}'::uuid,
  'failure', 'not_found', 'datajud_not_found', NULL, NULL, NULL,
  '${OBSERVED_AT}'::timestamptz, 404, 10, NULL
);
SQL
psql_cmd <"${TMP_DIR}/new-complete.sql" >/dev/null

JOB2_STATUS="$(psql_cmd -c "SELECT status FROM public.query_job WHERE id = '${JOB2_ID}';")"
JOB2_ATTEMPTS="$(psql_cmd -c "SELECT attempt_count FROM public.query_job WHERE id = '${JOB2_ID}';")"
if [[ "${JOB2_STATUS}" != "terminal_failure" || "${JOB2_ATTEMPTS}" -ne 2 ]]; then
  echo "Conclusão da nova lease inesperada: status=${JOB2_STATUS} attempts=${JOB2_ATTEMPTS}" >&2
  exit 1
fi

printf '%s\n' \
  "phase9-concurrency=PASS" \
  "scheduler_same_window_jobs=${JOB_COUNT}" \
  "claim_winners=$((CLAIM_LINES_A + CLAIM_LINES_B))" \
  "concurrent_completion_snapshots=${SNAPSHOT_COUNT}" \
  "concurrent_completion_exchanges=${EXCHANGE_COUNT}" \
  "stale_lease_rejected=1" \
  "new_lease_attempt=${JOB2_ATTEMPTS}"
