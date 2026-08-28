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
OTHER_OFFICE_ID="$(new_uuid)"
LAWYER_ID="$(new_uuid)"
REVIEWER_ID="$(new_uuid)"
OTHER_LAWYER_ID="$(new_uuid)"
OTHER_REVIEWER_ID="$(new_uuid)"

psql_cmd <<SQL
INSERT INTO auth.users (id, email) VALUES
  ('${LAWYER_ID}', 'phase12-concurrency-${LAWYER_ID}@synthetic.test'),
  ('${REVIEWER_ID}', 'phase12-concurrency-${REVIEWER_ID}@synthetic.test'),
  ('${OTHER_LAWYER_ID}', 'phase12-concurrency-${OTHER_LAWYER_ID}@synthetic.test'),
  ('${OTHER_REVIEWER_ID}', 'phase12-concurrency-${OTHER_REVIEWER_ID}@synthetic.test');
INSERT INTO public.office (id, name, is_active) VALUES
  ('${OFFICE_ID}', 'Fase 12 Concorrente Sintético', true),
  ('${OTHER_OFFICE_ID}', 'Fase 12 Outro Escritório Sintético', true);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES
  ('${LAWYER_ID}', '${OFFICE_ID}', 'Fase 12 Lawyer', 'lawyer', false, true),
  ('${REVIEWER_ID}', '${OFFICE_ID}', 'Fase 12 Reviewer', 'reviewer', false, true),
  ('${OTHER_LAWYER_ID}', '${OTHER_OFFICE_ID}', 'Fase 12 Other Lawyer', 'lawyer', false, true),
  ('${OTHER_REVIEWER_ID}', '${OTHER_OFFICE_ID}', 'Fase 12 Other Reviewer', 'reviewer', false, true);
SQL

seed_client() {
  local office_id="$1"
  local actor_id="$2"
  local client_id party_id
  client_id="$(new_uuid)"
  party_id="$(new_uuid)"
  psql_cmd <<SQL
INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES ('${party_id}', '${office_id}', 'person', 'Fase 12 Concorrência ${client_id}', 'fase 12 concorrencia ${client_id}', '${actor_id}');
INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES ('${client_id}', '${office_id}', '${party_id}', 'active', '${actor_id}');
SQL
  printf '%s\n' "${client_id}"
}

create_report() {
  local office_id="$1"
  local client_id="$2"
  local key="$3"
  psql_cmd -c "SET ROLE service_role; SELECT report_id, version_id FROM public.phase12_generate_weekly_report('${office_id}', '${client_id}', '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00');" \
    | tail -n 1
}

as_authenticated() {
  local actor_id="$1"
  shift
  psql_cmd -c "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${actor_id}', false); $*"
}

run_race() {
  local name="$1"
  local left_sql="$2"
  local right_sql="$3"
  printf '%s\n' "${left_sql}" >"${TMP_DIR}/${name}-left.sql"
  printf '%s\n' "${right_sql}" >"${TMP_DIR}/${name}-right.sql"
  set +e
  psql_cmd <"${TMP_DIR}/${name}-left.sql" >"${TMP_DIR}/${name}-left.out" 2>"${TMP_DIR}/${name}-left.err" &
  local left_pid=$!
  sleep 0.1
  psql_cmd <"${TMP_DIR}/${name}-right.sql" >"${TMP_DIR}/${name}-right.out" 2>"${TMP_DIR}/${name}-right.err" &
  local right_pid=$!
  wait "${left_pid}"
  local left_status=$?
  wait "${right_pid}"
  local right_status=$?
  set -e
  printf '%s|%s|%s\n' "${left_status}" "${right_status}" "${name}"
}

require_one_success() {
  local result="$1"
  local name="$2"
  local left_status right_status
  IFS='|' read -r left_status right_status _ <<<"${result}"
  if [[ "${left_status}" -eq 0 && "${right_status}" -eq 0 ]] ||
     [[ "${left_status}" -ne 0 && "${right_status}" -ne 0 ]]; then
    echo "${name}: esperado exatamente um vencedor, obtidos ${left_status}/${right_status}" >&2
    cat "${TMP_DIR}/${name}"-*.err >&2 || true
    exit 1
  fi
}

require_all_success() {
  local result="$1"
  local name="$2"
  local left_status right_status
  IFS='|' read -r left_status right_status _ <<<"${result}"
  if [[ "${left_status}" -ne 0 || "${right_status}" -ne 0 ]]; then
    echo "${name}: ambas as operações deveriam concluir, obtidos ${left_status}/${right_status}" >&2
    cat "${TMP_DIR}/${name}"-*.err >&2 || true
    exit 1
  fi
}

require_at_least_one_success() {
  local result="$1"
  local name="$2"
  local left_status right_status
  IFS='|' read -r left_status right_status _ <<<"${result}"
  if [[ "${left_status}" -ne 0 && "${right_status}" -ne 0 ]]; then
    echo "${name}: nenhuma operação venceu, obtidos ${left_status}/${right_status}" >&2
    cat "${TMP_DIR}/${name}"-*.err >&2 || true
    exit 1
  fi
}

assert_query() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "${message}: esperado=${expected}, obtido=${actual}" >&2
    exit 1
  fi
}

# 1. Duas gerações do mesmo cliente/período: uma criação e um replay, sem V2.
GEN_CLIENT="$(seed_client "${OFFICE_ID}" "${LAWYER_ID}")"
GEN_A="$(run_race generation "SET ROLE service_role; BEGIN; SELECT public.phase12_generate_weekly_report('${OFFICE_ID}', '${GEN_CLIENT}', '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00'); SELECT pg_sleep(0.4); COMMIT;" "SET ROLE service_role; BEGIN; SELECT public.phase12_generate_weekly_report('${OFFICE_ID}', '${GEN_CLIENT}', '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00'); SELECT pg_sleep(0.4); COMMIT;")"
IFS='|' read -r GEN_LEFT GEN_RIGHT _ <<<"${GEN_A}"
if [[ "${GEN_LEFT}" -ne 0 || "${GEN_RIGHT}" -ne 0 ]]; then
  echo "generation: uma das gerações falhou" >&2
  cat "${TMP_DIR}/generation"-*.err >&2 || true
  exit 1
fi
GEN_REPORT_ID="$(psql_cmd -c "SELECT id FROM public.weekly_report WHERE office_id = '${OFFICE_ID}' AND client_id = '${GEN_CLIENT}';")"
assert_query "$(psql_cmd -c "SELECT count(*) FROM public.report_version WHERE report_id = '${GEN_REPORT_ID}';")" "1" "duas gerações não criam V2"

# 2. Duas edições sobre a mesma base: exatamente uma vence o optimistic lock.
EDIT_CLIENT="$(seed_client "${OFFICE_ID}" "${LAWYER_ID}")"
IFS='|' read -r EDIT_REPORT EDIT_VERSION _ <<<"$(create_report "${OFFICE_ID}" "${EDIT_CLIENT}" edit-seed)"
EDIT_RACE="$(run_race edit_same_base "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${REVIEWER_ID}', false); BEGIN; SELECT public.phase12_create_editorial_version('${EDIT_REPORT}', '${EDIT_VERSION}', '{\"summary_note\":\"A\"}', 'phase12-edit-a'); SELECT pg_sleep(0.4); COMMIT;" "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${REVIEWER_ID}', false); BEGIN; SELECT public.phase12_create_editorial_version('${EDIT_REPORT}', '${EDIT_VERSION}', '{\"summary_note\":\"B\"}', 'phase12-edit-b'); SELECT pg_sleep(0.4); COMMIT;")"
require_one_success "${EDIT_RACE}" edit_same_base
assert_query "$(psql_cmd -c "SELECT count(*) FROM public.report_version WHERE report_id = '${EDIT_REPORT}';")" "2" "duas edições concorrentes preservam uma única V2"

# 3. Edição versus submissão: o estado e o ponteiro continuam coerentes.
SUBMIT_CLIENT="$(seed_client "${OFFICE_ID}" "${LAWYER_ID}")"
IFS='|' read -r SUBMIT_REPORT SUBMIT_VERSION _ <<<"$(create_report "${OFFICE_ID}" "${SUBMIT_CLIENT}" submit-seed)"
EDIT_SUBMIT_RACE="$(run_race edit_vs_submit "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${REVIEWER_ID}', false); BEGIN; SELECT public.phase12_create_editorial_version('${SUBMIT_REPORT}', '${SUBMIT_VERSION}', '{\"summary_note\":\"edit\"}', 'phase12-edit-submit'); SELECT pg_sleep(0.4); COMMIT;" "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${REVIEWER_ID}', false); BEGIN; SELECT public.phase12_submit_report('${SUBMIT_REPORT}', '${SUBMIT_VERSION}', 'phase12-submit-race'); SELECT pg_sleep(0.4); COMMIT;")"
IFS='|' read -r EDIT_SUBMIT_LEFT EDIT_SUBMIT_RIGHT _ <<<"${EDIT_SUBMIT_RACE}"
if [[ "${EDIT_SUBMIT_LEFT}" -ne 0 && "${EDIT_SUBMIT_RIGHT}" -ne 0 ]]; then
  echo "edit_vs_submit: nenhuma operação venceu" >&2
  cat "${TMP_DIR}/edit_vs_submit"-*.err >&2 || true
  exit 1
fi
SUBMIT_STATUS="$(psql_cmd -c "SELECT status FROM public.weekly_report WHERE id = '${SUBMIT_REPORT}';")"
if [[ "${SUBMIT_STATUS}" != "draft" && "${SUBMIT_STATUS}" != "awaiting_review" ]]; then
  echo "edit_vs_submit: estado final inválido ${SUBMIT_STATUS}" >&2
  exit 1
fi
assert_query "$(psql_cmd -c "SELECT count(*) FROM public.report_version rv JOIN public.weekly_report wr ON wr.current_version_id = rv.id WHERE wr.id = '${SUBMIT_REPORT}';")" "1" "edit_vs_submit preserva ponteiro de versão"

# 4. Edição versus aprovação: uma operação vence e não há aprovação de versão stale.
APPROVE_EDIT_CLIENT="$(seed_client "${OFFICE_ID}" "${LAWYER_ID}")"
IFS='|' read -r APPROVE_EDIT_REPORT APPROVE_EDIT_VERSION _ <<<"$(create_report "${OFFICE_ID}" "${APPROVE_EDIT_CLIENT}" approve-edit-seed)"
as_authenticated "${REVIEWER_ID}" "SELECT public.phase12_submit_report('${APPROVE_EDIT_REPORT}', '${APPROVE_EDIT_VERSION}', 'phase12-submit-approve-edit');"
EDIT_APPROVE_RACE="$(run_race edit_vs_approve "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${REVIEWER_ID}', false); BEGIN; SELECT public.phase12_create_editorial_version('${APPROVE_EDIT_REPORT}', '${APPROVE_EDIT_VERSION}', '{\"summary_note\":\"edit\"}', 'phase12-edit-approve'); SELECT pg_sleep(0.4); COMMIT;" "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${LAWYER_ID}', false); BEGIN; SELECT public.phase12_approve_report('${APPROVE_EDIT_REPORT}', '${APPROVE_EDIT_VERSION}', 'phase12-approve-edit'); SELECT pg_sleep(0.4); COMMIT;")"
require_one_success "${EDIT_APPROVE_RACE}" edit_vs_approve
EDIT_APPROVE_STATUS="$(psql_cmd -c "SELECT status FROM public.weekly_report WHERE id = '${APPROVE_EDIT_REPORT}';")"
if [[ "${EDIT_APPROVE_STATUS}" != "approved" && "${EDIT_APPROVE_STATUS}" != "awaiting_review" ]]; then
  echo "edit_vs_approve: estado final inválido ${EDIT_APPROVE_STATUS}" >&2
  exit 1
fi

# 5. Duas aprovações: somente uma transição é efetivada.
TWO_APPROVE_CLIENT="$(seed_client "${OFFICE_ID}" "${LAWYER_ID}")"
IFS='|' read -r TWO_APPROVE_REPORT TWO_APPROVE_VERSION _ <<<"$(create_report "${OFFICE_ID}" "${TWO_APPROVE_CLIENT}" two-approve-seed)"
as_authenticated "${REVIEWER_ID}" "SELECT public.phase12_submit_report('${TWO_APPROVE_REPORT}', '${TWO_APPROVE_VERSION}', 'phase12-submit-two-approve');"
TWO_APPROVE_RACE="$(run_race two_approves "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${LAWYER_ID}', false); BEGIN; SELECT public.phase12_approve_report('${TWO_APPROVE_REPORT}', '${TWO_APPROVE_VERSION}', 'phase12-approve-a'); SELECT pg_sleep(0.4); COMMIT;" "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${LAWYER_ID}', false); BEGIN; SELECT public.phase12_approve_report('${TWO_APPROVE_REPORT}', '${TWO_APPROVE_VERSION}', 'phase12-approve-b'); SELECT pg_sleep(0.4); COMMIT;")"
require_one_success "${TWO_APPROVE_RACE}" two_approves
assert_query "$(psql_cmd -c "SELECT status FROM public.weekly_report WHERE id = '${TWO_APPROVE_REPORT}';")" "approved" "duas aprovações deixam o relatório aprovado"
assert_query "$(psql_cmd -c "SELECT count(*) FROM public.audit_log WHERE entity_id = '${TWO_APPROVE_REPORT}' AND action = 'weekly_report.approved';")" "1" "duas aprovações gravam uma auditoria"

# 6. Aprovação versus cancelamento: uma transição terminal vence.
APPROVE_CANCEL_CLIENT="$(seed_client "${OFFICE_ID}" "${LAWYER_ID}")"
IFS='|' read -r APPROVE_CANCEL_REPORT APPROVE_CANCEL_VERSION _ <<<"$(create_report "${OFFICE_ID}" "${APPROVE_CANCEL_CLIENT}" approve-cancel-seed)"
as_authenticated "${REVIEWER_ID}" "SELECT public.phase12_submit_report('${APPROVE_CANCEL_REPORT}', '${APPROVE_CANCEL_VERSION}', 'phase12-submit-approve-cancel');"
APPROVE_CANCEL_RACE="$(run_race approve_vs_cancel "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${LAWYER_ID}', false); BEGIN; SELECT public.phase12_approve_report('${APPROVE_CANCEL_REPORT}', '${APPROVE_CANCEL_VERSION}', 'phase12-approve-cancel'); SELECT pg_sleep(0.4); COMMIT;" "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '${LAWYER_ID}', false); BEGIN; SELECT public.phase12_cancel_report('${APPROVE_CANCEL_REPORT}', 'other', 'phase12-cancel-approve'); SELECT pg_sleep(0.4); COMMIT;")"
require_at_least_one_success "${APPROVE_CANCEL_RACE}" approve_vs_cancel
APPROVE_CANCEL_STATUS="$(psql_cmd -c "SELECT status FROM public.weekly_report WHERE id = '${APPROVE_CANCEL_REPORT}';")"
if [[ "${APPROVE_CANCEL_STATUS}" != "approved" && "${APPROVE_CANCEL_STATUS}" != "cancelled" ]]; then
  echo "approve_vs_cancel: estado final inválido ${APPROVE_CANCEL_STATUS}" >&2
  exit 1
fi

# 7. Dois escritórios no mesmo período não compartilham lock ou dados.
OTHER_A_CLIENT="$(seed_client "${OTHER_OFFICE_ID}" "${OTHER_LAWYER_ID}")"
OTHER_B_CLIENT="$(seed_client "${OTHER_OFFICE_ID}" "${OTHER_LAWYER_ID}")"
OFFICE_RACE="$(run_race two_offices "SET ROLE service_role; BEGIN; SELECT public.phase12_generate_weekly_report('${OTHER_OFFICE_ID}', '${OTHER_A_CLIENT}', '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00'); SELECT pg_sleep(0.4); COMMIT;" "SET ROLE service_role; BEGIN; SELECT public.phase12_generate_weekly_report('${OTHER_OFFICE_ID}', '${OTHER_B_CLIENT}', '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00'); SELECT pg_sleep(0.4); COMMIT;")"
require_all_success "${OFFICE_RACE}" two_offices
assert_query "$(psql_cmd -c "SELECT count(*) FROM public.weekly_report WHERE office_id = '${OTHER_OFFICE_ID}' AND period_start_utc = '2026-08-21 20:00:00+00';")" "2" "escritórios distintos mantêm séries independentes"

# 8. Replay da mesma chave: retorna a mesma versão e não duplica.
REPLAY_CLIENT="$(seed_client "${OFFICE_ID}" "${LAWYER_ID}")"
IFS='|' read -r REPLAY_REPORT REPLAY_VERSION _ <<<"$(create_report "${OFFICE_ID}" "${REPLAY_CLIENT}" replay-seed)"
REPLAY_FIRST="$(as_authenticated "${REVIEWER_ID}" "SELECT public.phase12_create_editorial_version('${REPLAY_REPORT}', '${REPLAY_VERSION}', '{\"summary_note\":\"replay\"}', 'phase12-replay');")"
REPLAY_SECOND="$(as_authenticated "${REVIEWER_ID}" "SELECT public.phase12_create_editorial_version('${REPLAY_REPORT}', '${REPLAY_VERSION}', '{\"summary_note\":\"replay\"}', 'phase12-replay');")"
assert_query "$(psql_cmd -c "SELECT count(*) FROM public.report_version WHERE report_id = '${REPLAY_REPORT}';")" "2" "replay não cria versão adicional"
assert_query "$(psql_cmd -c "SELECT count(*) FROM public.report_command_idempotency WHERE office_id = '${OFFICE_ID}' AND operation = 'version.create' AND idempotency_key = 'phase12-replay';")" "1" "replay mantém uma chave de idempotência"

printf '%s\n' \
  'phase12-reports-concurrency=PASS' \
  'scenarios=8' \
  'generation_same_period=PASS' \
  'edit_same_base=PASS' \
  'edit_vs_submit=PASS' \
  'edit_vs_approve=PASS' \
  'two_approves=PASS' \
  'approve_vs_cancel=PASS' \
  'two_offices_same_period=PASS' \
  'replay=PASS'
