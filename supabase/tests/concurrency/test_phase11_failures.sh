#!/usr/bin/env bash
set -euo pipefail

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
EMAIL="phase11-concurrency-${USER_ID}@synthetic.test"

psql_cmd <<SQL
INSERT INTO auth.users (id, email) VALUES ('${USER_ID}', '${EMAIL}');
INSERT INTO public.office (id, name, is_active) VALUES ('${OFFICE_ID}', 'Fase 11 Concorrente Sintético', true);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES ('${USER_ID}', '${OFFICE_ID}', 'Fase 11 Failure Worker', 'lawyer', false, true);
INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES ('${PARTY_ID}', '${OFFICE_ID}', 'person', 'Fase 11 Party', 'fase 11 party', '${USER_ID}');
INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES ('${CLIENT_ID}', '${OFFICE_ID}', '${PARTY_ID}', 'active', '${USER_ID}');
INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
) VALUES (
  '${PROCESS_ID}', '${OFFICE_ID}', '${CLIENT_ID}', '11000000000000000021',
  'TJ-SYNTHETIC', 'Phase11', true, 'active', 'active', '${USER_ID}'
);
SQL

cat >"${TMP_DIR}/record.sql" <<SQL
BEGIN;
SELECT public.phase11_record_failure_event_internal(
  '${OFFICE_ID}', '${PROCESS_ID}', 'provider', 'datajud_sandbox',
  'process_observation', 'provider', 'provider_transient', 'datajud_timeout',
  '{"source":"datajud","capability":"process_observation","failure_stage":"provider"}',
  NULL, NULL, NULL, NULL, 'provider_exchange', 'shared-provider-exchange'
);
SELECT pg_sleep(1);
COMMIT;
SQL
cp "${TMP_DIR}/record.sql" "${TMP_DIR}/record-b.sql"
psql_cmd <"${TMP_DIR}/record.sql" >"${TMP_DIR}/record-a.out" &
PID_A=$!
sleep 0.1
psql_cmd <"${TMP_DIR}/record-b.sql" >"${TMP_DIR}/record-b.out" &
PID_B=$!
wait "${PID_A}"
wait "${PID_B}"

INCIDENT_COUNT="$(psql_cmd -c "SELECT count(*) FROM public.failure_incident WHERE office_id = '${OFFICE_ID}';")"
OCCURRENCE_COUNT="$(psql_cmd -c "SELECT occurrence_count FROM public.failure_incident WHERE office_id = '${OFFICE_ID}';")"
FAILURE_EVENTS="$(psql_cmd -c "SELECT count(*) FROM public.failure_occurrence WHERE office_id = '${OFFICE_ID}' AND event_kind = 'failure_observed';")"
OUTBOX_EVENTS="$(psql_cmd -c "SELECT count(*) FROM public.notification_outbox WHERE office_id = '${OFFICE_ID}' AND event_kind = 'failure_observed';")"
if [[ "${INCIDENT_COUNT}" -ne 1 || "${OCCURRENCE_COUNT}" -ne 1 || "${FAILURE_EVENTS}" -ne 1 || "${OUTBOX_EVENTS}" -ne 2 ]]; then
  echo "Deduplicação concorrente inesperada: incidents=${INCIDENT_COUNT} occurrence_count=${OCCURRENCE_COUNT} failure_events=${FAILURE_EVENTS} outbox=${OUTBOX_EVENTS}" >&2
  cat "${TMP_DIR}/record-a.out" "${TMP_DIR}/record-b.out" >&2
  exit 1
fi

printf '%s\n' \
  "phase11-failures-concurrency=PASS" \
  "incidents=${INCIDENT_COUNT}" \
  "occurrence_count=${OCCURRENCE_COUNT}" \
  "failure_events=${FAILURE_EVENTS}" \
  "outbox_events=${OUTBOX_EVENTS}"
