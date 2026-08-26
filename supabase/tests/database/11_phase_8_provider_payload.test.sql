BEGIN;

INSERT INTO auth.users (id, email)
VALUES
  ('81000000-0000-4000-8000-000000000001', 'phase8-lawyer@example.test'),
  ('81000000-0000-4000-8000-000000000002', 'phase8-operator@example.test'),
  ('81000000-0000-4000-8000-000000000003', 'phase8-reviewer@example.test'),
  ('81000000-0000-4000-8000-000000000004', 'phase8-auditor@example.test'),
  ('81000000-0000-4000-8000-000000000005', 'phase8-owner-auditor@example.test'),
  ('81000000-0000-4000-8000-000000000006', 'phase8-inactive@example.test'),
  ('81000000-0000-4000-8000-000000000007', 'phase8-inactive-office@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('81000000-0000-4000-9000-000000000001', 'Phase 8 Active Office', true),
  ('81000000-0000-4000-9000-000000000002', 'Phase 8 Other Office', true),
  ('81000000-0000-4000-9000-000000000003', 'Phase 8 Inactive Office', false)
ON CONFLICT (id) DO UPDATE SET is_active = excluded.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES
  ('81000000-0000-4000-8000-000000000001', '81000000-0000-4000-9000-000000000001', 'Phase 8 Lawyer', 'lawyer', false, true),
  ('81000000-0000-4000-8000-000000000002', '81000000-0000-4000-9000-000000000001', 'Phase 8 Operator', 'operator', false, true),
  ('81000000-0000-4000-8000-000000000003', '81000000-0000-4000-9000-000000000001', 'Phase 8 Reviewer', 'reviewer', false, true),
  ('81000000-0000-4000-8000-000000000004', '81000000-0000-4000-9000-000000000001', 'Phase 8 Auditor', 'auditor', false, true),
  ('81000000-0000-4000-8000-000000000005', '81000000-0000-4000-9000-000000000001', 'Phase 8 Owner Auditor', 'auditor', true, true),
  ('81000000-0000-4000-8000-000000000006', '81000000-0000-4000-9000-000000000001', 'Phase 8 Inactive User', 'lawyer', false, false),
  ('81000000-0000-4000-8000-000000000007', '81000000-0000-4000-9000-000000000003', 'Phase 8 Inactive Office User', 'lawyer', false, true)
ON CONFLICT (id) DO UPDATE SET office_id = excluded.office_id, role = excluded.role, is_owner = excluded.is_owner, is_active = excluded.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES
  ('81000000-0000-4000-a000-000000000001', '81000000-0000-4000-9000-000000000001', 'person', 'Phase 8 Party', 'phase 8 party', '81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-a000-000000000002', '81000000-0000-4000-9000-000000000002', 'person', 'Phase 8 Other Party', 'phase 8 other party', '81000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES
  ('81000000-0000-4000-b000-000000000001', '81000000-0000-4000-9000-000000000001', '81000000-0000-4000-a000-000000000001', '81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-b000-000000000002', '81000000-0000-4000-9000-000000000002', '81000000-0000-4000-a000-000000000002', '81000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (id, office_id, client_id, cnj_number, tribunal, system, is_public, monitoring_status, status, created_by)
VALUES
  ('81000000-0000-4000-c000-000000000001', '81000000-0000-4000-9000-000000000001', '81000000-0000-4000-b000-000000000001', '81000000000000000001', 'TJ-SYNTHETIC', 'Sandbox', true, 'paused', 'active', '81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-c000-000000000002', '81000000-0000-4000-9000-000000000001', '81000000-0000-4000-b000-000000000001', '81000000000000000002', 'TJ-SYNTHETIC', 'Sandbox', false, 'paused', 'active', '81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-c000-000000000003', '81000000-0000-4000-9000-000000000002', '81000000-0000-4000-b000-000000000002', '81000000000000000003', 'TJ-SYNTHETIC', 'Sandbox', true, 'paused', 'active', '81000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

SELECT plan(36);

SELECT ok(has_table_privilege('authenticated', 'public.provider_exchange', 'SELECT'), 'authenticated can SELECT provider exchange through RLS');
SELECT ok(not has_table_privilege('authenticated', 'public.provider_exchange', 'INSERT'), 'authenticated cannot INSERT provider exchange directly');
SELECT ok(not has_table_privilege('authenticated', 'public.provider_exchange', 'UPDATE'), 'authenticated cannot UPDATE provider exchange directly');
SELECT ok(not has_table_privilege('authenticated', 'public.provider_exchange', 'DELETE'), 'authenticated cannot DELETE provider exchange directly');
SELECT ok(not has_table_privilege('authenticated', 'public.raw_provider_payload', 'SELECT'), 'authenticated cannot SELECT raw payload directly');
SELECT ok(not has_table_privilege('authenticated', 'public.raw_provider_payload', 'INSERT'), 'authenticated cannot INSERT raw payload directly');
SELECT ok(has_function_privilege('authenticated', 'public.record_provider_exchange(uuid,text,text,integer,text,text,text,text,text,text,jsonb,jsonb,text,timestamptz)'::regprocedure, 'EXECUTE'), 'authenticated can execute controlled provider writer');
SELECT ok(has_function_privilege('authenticated', 'public.get_provider_raw_payload(uuid)'::regprocedure, 'EXECUTE'), 'authenticated can execute protected raw reader');
SELECT ok(not has_function_privilege('authenticated', 'public.write_provider_audit(text,text,uuid,jsonb)'::regprocedure, 'EXECUTE'), 'authenticated cannot execute internal provider audit helper');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);

SELECT lives_ok($$
  SELECT public.record_provider_exchange(
    '81000000-0000-4000-c000-000000000001',
    'datajud_sandbox', 'datajud', 1,
    '81000000000000000001', '81000000-0000-4000-a100-000000000001',
    'synthetic-request-fingerprint-001', 'observation', 'observed', NULL,
    '{"kind":"observation","data":{"processRef":"81000000000000000001"}}'::jsonb,
    '{"outcome":"observation","processRef":"81000000000000000001","movements":[]}'::jsonb,
    'provider-payload-v1', '2026-01-01T00:00:00Z'
  )
$$, 'lawyer records a synthetic public DataJud exchange and payload');

SELECT is((SELECT count(*)::integer FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), 1, 'one provider exchange is persisted');

RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.raw_provider_payload WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), 1, 'one raw payload is persisted');
SELECT is((SELECT payload_hash FROM public.raw_provider_payload WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), encode(extensions.digest(convert_to((SELECT payload::text FROM public.raw_provider_payload WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), 'UTF8'), 'sha256'), 'hex'), 'raw payload hash matches stored bytes');
SELECT is((SELECT payload_bytes FROM public.raw_provider_payload WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), octet_length(convert_to((SELECT payload::text FROM public.raw_provider_payload WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), 'UTF8')), 'raw payload byte length is consistent');
SELECT is((SELECT count(*)::integer FROM public.audit_log WHERE action IN ('provider.exchange.recorded', 'provider.payload.recorded') AND entity_id IN ((SELECT id FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), (SELECT id FROM public.raw_provider_payload WHERE correlation_id = '81000000-0000-4000-a100-000000000001'))), 2, 'provider exchange and payload audit rows are both present');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
SELECT lives_ok($$
  SELECT public.record_provider_exchange(
    '81000000-0000-4000-c000-000000000001',
    'datajud_sandbox', 'datajud', 1,
    '81000000000000000001', '81000000-0000-4000-a100-000000000001',
    'synthetic-request-fingerprint-001', 'observation', 'observed', NULL,
    '{"kind":"observation","data":{"processRef":"81000000000000000001"}}'::jsonb,
    '{"outcome":"observation","processRef":"81000000000000000001","movements":[]}'::jsonb,
    'provider-payload-v1', '2026-01-01T00:00:00Z'
  )
$$, 'identical replay is idempotent');
SELECT is((SELECT count(*)::integer FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'), 1, 'identical replay does not create a second exchange');

SELECT throws_ok($$
  SELECT public.record_provider_exchange(
    '81000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
    '99999999999999999999', '81000000-0000-4000-a100-000000000002',
    'synthetic-request-fingerprint-002', 'observation', 'observed', NULL,
    '{"kind":"observation","data":{"processRef":"99999999999999999999"}}'::jsonb,
    '{"outcome":"observation","processRef":"99999999999999999999"}'::jsonb,
    'provider-payload-v1', '2026-01-01T00:00:00Z'
  )
$$, '23514', NULL, 'processRef mismatch is rejected');
SELECT throws_ok($$
  SELECT public.record_provider_exchange(
    '81000000-0000-4000-c000-000000000001', 'manual_observation', 'manual', 1,
    '81000000000000000001', '81000000-0000-4000-a100-000000000009',
    'synthetic-request-fingerprint-009', 'observation', 'observed', NULL,
    '{"kind":"observation","data":{"processRef":"81000000000000000001"}}'::jsonb,
    '{"processRef":"81000000000000000001"}'::jsonb,
    'provider-payload-v1', '2026-01-01T00:00:00Z'
  )
$$, '42501', NULL, 'manual provider entry remains blocked without D-022 action');

SELECT throws_ok($$
  SELECT public.record_provider_exchange(
    '81000000-0000-4000-c000-000000000002', 'datajud_sandbox', 'datajud', 1,
    '81000000000000000002', '81000000-0000-4000-a100-000000000003',
    'synthetic-request-fingerprint-003', 'observation', 'observed', NULL,
    '{"kind":"observation","changed":true}'::jsonb,
    '{"outcome":"observation","processRef":"81000000000000000002"}'::jsonb,
    'provider-payload-v1', '2026-01-01T00:00:00Z'
  )
$$, '42501', NULL, 'sealed process is blocked before persistence');
SELECT throws_ok($$
  SELECT public.record_provider_exchange(
    '81000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
    '81000000000000000001', '81000000-0000-4000-a100-000000000004',
    'synthetic-request-fingerprint-004', 'observation', 'observed', NULL,
    '{"kind":"observation","changed":true}'::jsonb,
    '{"outcome":"observation","processRef":"81000000000000000001","Authorization":"Bearer secret"}'::jsonb,
    'provider-payload-v1', '2026-01-01T00:00:00Z'
  )
$$, '22023', NULL, 'comparison or sensitive raw payload is rejected');
SELECT throws_ok($$
  SELECT public.record_provider_exchange(
    '81000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
    '81000000000000000001', '81000000-0000-4000-a100-000000000005',
    'synthetic-request-fingerprint-005', 'observation', 'observed', NULL,
    '{"kind":"observation","data":{"processRef":"81000000000000000001"}}'::jsonb,
    jsonb_build_object('outcome', 'observation', 'processRef', '81000000000000000001', 'large', repeat('x', 262145)) ,
    'provider-payload-v1', '2026-01-01T00:00:00Z'
  )
$$, '22023', NULL, 'oversized raw payload is rejected');

SELECT is((SELECT count(*)::integer FROM public.get_provider_raw_payload((SELECT id FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'))), 1, 'lawyer can read raw payload through protected RPC');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000002', true);
SELECT is((SELECT count(*)::integer FROM public.provider_exchange WHERE office_id = '81000000-0000-4000-9000-000000000001'), 1, 'operator can view same-office exchange rows');
SELECT throws_ok($$SELECT * FROM public.get_provider_raw_payload((SELECT id FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'))$$, '42501', NULL, 'operator cannot read raw payload');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000003', true);
SELECT is((SELECT count(*)::integer FROM public.provider_exchange), 1, 'reviewer sees same-office exchange but not cross-office');
SELECT throws_ok($$SELECT * FROM public.get_provider_raw_payload((SELECT id FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'))$$, '42501', NULL, 'reviewer cannot read raw payload');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000004', true);
SELECT is((SELECT count(*)::integer FROM public.provider_exchange), 0, 'auditor has no operational exchange access');
SELECT throws_ok($$SELECT * FROM public.get_provider_raw_payload((SELECT id FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'))$$, '42501', NULL, 'auditor cannot read raw payload');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000005', true);
SELECT is((SELECT count(*)::integer FROM public.provider_exchange), 0, 'owner-auditor does not gain operational exchange access');
SELECT throws_ok($$SELECT * FROM public.get_provider_raw_payload((SELECT id FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000001'))$$, '42501', NULL, 'owner-auditor cannot read raw payload');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000006', true);
SELECT throws_ok($$SELECT public.record_provider_exchange('81000000-0000-4000-c000-000000000001','datajud_sandbox','datajud',1,'81000000000000000001','81000000-0000-4000-a100-000000000006','synthetic-request-fingerprint-006','failure','not_found','datajud_not_found',NULL,NULL,NULL,'2026-01-01T00:00:00Z')$$, '42501', NULL, 'inactive user cannot record exchange');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000007', true);
SELECT throws_ok($$SELECT public.record_provider_exchange('81000000-0000-4000-c000-000000000001','datajud_sandbox','datajud',1,'81000000000000000001','81000000-0000-4000-a100-000000000007','synthetic-request-fingerprint-007','failure','not_found','datajud_not_found',NULL,NULL,NULL,'2026-01-01T00:00:00Z')$$, '42501', NULL, 'inactive office user cannot record exchange');

RESET ROLE;

CREATE OR REPLACE FUNCTION public.phase8_force_provider_audit_failure()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.action = 'provider.exchange.recorded' THEN
    RAISE EXCEPTION 'forced provider audit failure' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER phase8_force_provider_audit_failure_trigger
BEFORE INSERT ON public.audit_log
FOR EACH ROW EXECUTE FUNCTION public.phase8_force_provider_audit_failure();

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
SELECT throws_ok($$SELECT public.record_provider_exchange('81000000-0000-4000-c000-000000000001','datajud_sandbox','datajud',1,'81000000000000000001','81000000-0000-4000-a100-000000000008','synthetic-request-fingerprint-008','failure','not_found','datajud_not_found',NULL,NULL,NULL,'2026-01-01T00:00:00Z')$$, 'P0001', NULL, 'provider exchange rolls back when audit insert fails');
SELECT is((SELECT count(*)::integer FROM public.provider_exchange WHERE correlation_id = '81000000-0000-4000-a100-000000000008'), 0, 'audit failure leaves no provider exchange row');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.raw_provider_payload WHERE correlation_id = '81000000-0000-4000-a100-000000000008'), 0, 'audit failure leaves no raw payload row');

SELECT * FROM finish();
ROLLBACK;
