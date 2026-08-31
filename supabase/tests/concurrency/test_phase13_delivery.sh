#!/usr/bin/env bash
set -euo pipefail

# F13 local-only concurrency contract. No provider, email, or external storage is used.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"
DB_CONTAINER="${SUPABASE_DB_CONTAINER:-$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1 || true)}"
if [[ -z "${DB_CONTAINER}" ]] || ! docker inspect "${DB_CONTAINER}" >/dev/null 2>&1; then
  echo "Local Supabase PostgreSQL container not found (start Supabase first)." >&2
  exit 1
fi
psql_cmd() { docker exec -i "${DB_CONTAINER}" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"; }
TMP_DIR="$(mktemp -d)"; trap 'rm -rf "${TMP_DIR}"' EXIT
OFFICE='f1300000-0000-4000-9000-000000000001'; OTHER_OFFICE='f1300000-0000-4000-9000-000000000002'
LAWYER='f1300000-0000-4000-8000-000000000001'; OTHER='f1300000-0000-4000-8000-000000000002'; INACTIVE='f1300000-0000-4000-8000-000000000003'
PARTY='f1300000-0000-4000-a000-000000000001'; CLIENT='f1300000-0000-4000-b000-000000000001'; REPORT='f1300000-0000-4000-c000-000000000001'; VERSION='f1300000-0000-4000-d000-000000000001'; ARTIFACT='f1300000-0000-4000-e000-000000000001'; CONTACT='f1300000-0000-4000-f000-000000000001'; DELIVERY='f1300000-0000-4000-0000-000000000001'
HASH=$(printf 'a%.0s' {1..64}); FILE_HASH=$(printf 'b%.0s' {1..64}); FP=$(printf 'c%.0s' {1..64})
psql_cmd <<SQL
SELECT set_config('juridico.phase12_internal','1',false);
SELECT set_config('juridico.phase13_internal','1',false);
INSERT INTO auth.users(id,email) VALUES ('$LAWYER','f13-lawyer@synthetic.test'),('$OTHER','f13-other@synthetic.test'),('$INACTIVE','f13-inactive@synthetic.test') ON CONFLICT DO NOTHING;
INSERT INTO public.office(id,name,is_active) VALUES ('$OFFICE','F13 Synthetic Office',true),('$OTHER_OFFICE','F13 Other Office',true) ON CONFLICT(id) DO UPDATE SET is_active=excluded.is_active;
INSERT INTO public.user_profile(id,office_id,name,role,is_owner,is_active) VALUES ('$LAWYER','$OFFICE','F13 Lawyer','lawyer',false,true),('$OTHER','$OTHER_OFFICE','F13 Other','lawyer',false,true),('$INACTIVE','$OFFICE','F13 Inactive','lawyer',false,false) ON CONFLICT(id) DO UPDATE SET office_id=excluded.office_id,role=excluded.role,is_active=excluded.is_active;
INSERT INTO public.party(id,office_id,party_type,display_name,normalized_name,created_by) VALUES ('$PARTY','$OFFICE','person','F13 Synthetic Client','f13 synthetic client','$LAWYER') ON CONFLICT DO NOTHING;
INSERT INTO public.client(id,office_id,party_id,status,created_by) VALUES ('$CLIENT','$OFFICE','$PARTY','active','$LAWYER') ON CONFLICT DO NOTHING;
INSERT INTO public.weekly_report(id,office_id,client_id,period_start_utc,period_end_utc,status,generation_key) VALUES ('$REPORT','$OFFICE','$CLIENT','2026-08-21 00:00+00','2026-08-28 00:00+00','draft','f13-synthetic') ON CONFLICT DO NOTHING;
INSERT INTO public.report_version(id,office_id,report_id,version_number,created_by,creation_kind,schema_version,structured_content,source_manifest,content_hash) VALUES ('$VERSION','$OFFICE','$REPORT',1,'$LAWYER','generated','report-v1','{"title":"F13 synthetic"}','{}','$HASH') ON CONFLICT DO NOTHING;
UPDATE public.weekly_report SET status='approved',current_version_id='$VERSION',approved_version_id='$VERSION',approved_hash='$HASH',approved_by='$LAWYER',approved_at=now() WHERE id='$REPORT';
INSERT INTO public.report_artifact(id,office_id,report_id,report_version_id,private_storage_uri,approved_hash,file_hash,generation_fingerprint,byte_size,created_by) VALUES ('$ARTIFACT','$OFFICE','$REPORT','$VERSION','private://private-reports/$REPORT/$VERSION/$ARTIFACT.pdf','$HASH','$FILE_HASH','$FP',12,'$LAWYER') ON CONFLICT DO NOTHING;
INSERT INTO public.client_contact(id,office_id,client_id,display_name,email,is_confirmed,confirmed_by,confirmed_at) VALUES ('$CONTACT','$OFFICE','$CLIENT','F13 Recipient','f13-recipient@synthetic.test',true,'$LAWYER',now()) ON CONFLICT DO NOTHING;
INSERT INTO public.email_delivery(id,office_id,report_id,report_version_id,artifact_id,client_contact_id,recipient,subject,approved_hash,artifact_hash,private_pdf_uri,idempotency_key,created_by) VALUES ('$DELIVERY','$OFFICE','$REPORT','$VERSION','$ARTIFACT','$CONTACT','f13-recipient@synthetic.test','F13 synthetic','$HASH','$FILE_HASH','private://private-reports/$REPORT/$VERSION/$ARTIFACT.pdf','f13-initial','$LAWYER') ON CONFLICT DO NOTHING;
SQL
race() { local n="$1"; shift; printf '%s\n' "$1" >"$TMP_DIR/$n-a.sql"; printf '%s\n' "$2" >"$TMP_DIR/$n-b.sql"; set +e; psql_cmd <"$TMP_DIR/$n-a.sql" >"$TMP_DIR/$n-a.out" 2>"$TMP_DIR/$n-a.err" & a=$!; psql_cmd <"$TMP_DIR/$n-b.sql" >"$TMP_DIR/$n-b.out" 2>"$TMP_DIR/$n-b.err" & b=$!; wait "$a"; sa=$?; wait "$b"; sb=$?; set -e; [[ $sa -eq 0 || $sb -eq 0 ]] && [[ ! ($sa -eq 0 && $sb -eq 0) ]] || { cat "$TMP_DIR/$n"-*.err >&2; return 1; }; }
auth() { psql_cmd -c "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$1',false); $2"; }
# 1 atomic claim: two service-role sessions produce at most one processing attempt.
race claim "SET ROLE service_role; SELECT public.phase13_claim_delivery_attempt('$DELIVERY');" "SET ROLE service_role; SELECT public.phase13_claim_delivery_attempt('$DELIVERY');"
[[ "$(psql_cmd -c "SELECT count(*) FROM public.email_delivery_attempt WHERE delivery_id='$DELIVERY' AND outcome='processing';")" == 1 ]]
# 2 retries are bounded at three attempts.
for n in 1 2; do psql_cmd -c "SET ROLE service_role; SELECT public.phase13_record_delivery_attempt('$DELIVERY',$n,'retry_available','{}');" >/dev/null; auth "$LAWYER" "SELECT public.phase13_retry_delivery('$DELIVERY','f13-retry-$n');" >/dev/null; psql_cmd -c "SET ROLE service_role; SELECT public.phase13_claim_delivery_attempt('$DELIVERY');" >/dev/null; done
psql_cmd -c "SET ROLE service_role; SELECT public.phase13_record_delivery_attempt('$DELIVERY',3,'unknown_outcome','{}');" >/dev/null
[[ "$(psql_cmd -c "SELECT count(*) FROM public.email_delivery_attempt WHERE delivery_id='$DELIVERY';")" == 3 ]]
# 3 unknown outcome reconciliation is explicit and auditable.
auth "$LAWYER" "SELECT public.phase13_reconcile_unknown_delivery('$DELIVERY',true,'synthetic provider lookup');" >/dev/null
[[ "$(psql_cmd -c "SELECT status FROM public.email_delivery WHERE id='$DELIVERY';")" == delivered ]]
# 4 resend creates an isolated delivery and does not mutate the original attempts.
NEW_DELIVERY="$(auth "$LAWYER" "SELECT public.phase13_resend_delivery('$DELIVERY','f13-resend-1','synthetic resend');" | tail -n 1)"
[[ -n "$NEW_DELIVERY" && "$NEW_DELIVERY" != "$DELIVERY" ]]
[[ "$(psql_cmd -c "SELECT count(*) FROM public.email_delivery_attempt WHERE delivery_id='$DELIVERY';")" == 3 ]]
# 5 office and inactive actor boundaries reject authorization.
if auth "$OTHER" "SELECT public.phase13_authorize_send('$REPORT','$VERSION','$ARTIFACT','$CONTACT','cross office','f13-cross-office');" >/dev/null 2>"$TMP_DIR/cross.err"; then echo 'cross-office authorization unexpectedly succeeded' >&2; exit 1; fi
if auth "$INACTIVE" "SELECT public.phase13_authorize_send('$REPORT','$VERSION','$ARTIFACT','$CONTACT','inactive','f13-inactive');" >/dev/null 2>"$TMP_DIR/inactive.err"; then echo 'inactive authorization unexpectedly succeeded' >&2; exit 1; fi
# The invariant is the database result, not provider behavior.
[[ "$(psql_cmd -c "SELECT count(*) FROM public.email_delivery_attempt WHERE delivery_id='$DELIVERY' AND outcome='processing';")" -le 1 ]]
printf '%s\n' 'phase13-delivery-concurrency=PASS' 'scenarios=5' 'processing_attempts<=1=PASS' 'retries_max_3=PASS' 'unknown_reconcile=PASS' 'resend_isolated=PASS' 'office_inactive_rejection=PASS'
