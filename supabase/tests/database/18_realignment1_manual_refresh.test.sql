BEGIN;

SELECT plan(18);

CREATE OR REPLACE FUNCTION set_auth_user(user_id UUID) RETURNS void AS $$
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', user_id::text, true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', user_id), true);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION set_service_role() RETURNS void AS $$
BEGIN
    PERFORM set_config('role', 'service_role', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{"role": "service_role"}', true);
END;
$$ LANGUAGE plpgsql;

-- 1. Functions exist
SELECT has_function('public', 'realignment1_request_process_refresh', ARRAY['uuid'], 'realignment1_request_process_refresh exists');
SELECT has_function('public', 'realignment1_claim_query_job', ARRAY['text', 'uuid', 'integer'], 'realignment1_claim_query_job exists');

-- 2. Grants & security
SELECT is_definer('public', 'realignment1_request_process_refresh', ARRAY['uuid'], 'is security definer');
-- Check grants for authenticated on request RPC
SELECT ok(
  has_function_privilege('authenticated', 'public.realignment1_request_process_refresh(uuid)', 'EXECUTE'),
  'authenticated has EXECUTE on realignment1_request_process_refresh'
);
-- Check targeted claim is backend-only (service_role only, NOT authenticated)
SELECT ok(
  NOT has_function_privilege('authenticated', 'public.realignment1_claim_query_job(text, uuid, integer)', 'EXECUTE'),
  'authenticated CANNOT EXECUTE realignment1_claim_query_job'
);
SELECT ok(
  NOT has_function_privilege('anon', 'public.realignment1_claim_query_job(text, uuid, integer)', 'EXECUTE'),
  'anon CANNOT EXECUTE realignment1_claim_query_job'
);
SELECT ok(
  has_function_privilege('service_role', 'public.realignment1_claim_query_job(text, uuid, integer)', 'EXECUTE'),
  'service_role HAS EXECUTE on realignment1_claim_query_job'
);

-- 3. Check partial unique index
SELECT has_index(
  'public',
  'query_job',
  'query_job_single_active_manual_refresh_idx',
  'query_job_single_active_manual_refresh_idx index exists'
);

-- 4. Setup test data
SELECT set_config('role', 'postgres', true);

INSERT INTO auth.users (id, email)
VALUES ('91000000-0000-4000-8000-000000000091', 'realignment1-lawyer@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES ('91000000-0000-4000-9000-000000000091', 'Realignment1 Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = excluded.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES ('91000000-0000-4000-8000-000000000091', '91000000-0000-4000-9000-000000000091', 'Realignment1 Lawyer', 'lawyer', true, true)
ON CONFLICT (id) DO UPDATE SET office_id = excluded.office_id, role = excluded.role, is_owner = excluded.is_owner, is_active = excluded.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES ('91000000-0000-4000-a000-000000000091', '91000000-0000-4000-9000-000000000091', 'person', 'Realignment1 Party', 'realignment1 party', '91000000-0000-4000-8000-000000000091')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES ('91000000-0000-4000-b000-000000000091', '91000000-0000-4000-9000-000000000091', '91000000-0000-4000-a000-000000000091', '91000000-0000-4000-8000-000000000091')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, is_public, monitoring_status, status, created_by
) VALUES (
  '91000000-0000-4000-c000-000000000091',
  '91000000-0000-4000-9000-000000000091',
  '91000000-0000-4000-b000-000000000091',
  '00044531220268160000',
  'TJPR',
  true,
  'paused',
  'active',
  '91000000-0000-4000-8000-000000000091'
) ON CONFLICT (id) DO NOTHING;

-- 5. Test realignment1_request_process_refresh as authenticated user
SELECT set_auth_user('91000000-0000-4000-8000-000000000091');

SELECT lives_ok(
  $$ SELECT * FROM public.realignment1_request_process_refresh('91000000-0000-4000-c000-000000000091') $$,
  'request_process_refresh creates a new job for active public process'
);

-- Check that a second call returns the same job with is_reused = true
SELECT is(
  (SELECT is_reused FROM public.realignment1_request_process_refresh('91000000-0000-4000-c000-000000000091')),
  true,
  'second request returns is_reused = true'
);

SELECT set_config('role', 'postgres', true);

-- Check audit log contains human audit event
SELECT ok(
  EXISTS(
    SELECT 1 FROM public.audit_log
     WHERE action = 'query_job.manual_refresh_requested'
       AND actor_user_id = '91000000-0000-4000-8000-000000000091'
       AND entity_type = 'query_job'
  ),
  'human user audit log entry recorded for manual_refresh'
);

-- 6. Test targeted claim as service_role
DO $$
DECLARE
  v_job_id UUID;
  v_claim RECORD;
BEGIN
  SELECT id INTO v_job_id FROM public.query_job WHERE job_kind = 'manual_refresh' LIMIT 1;
  PERFORM set_service_role();
  SELECT * INTO v_claim FROM public.realignment1_claim_query_job('worker-backend-1', v_job_id, 30000);

  IF v_claim.job_id IS NULL THEN
    RAISE EXCEPTION 'Targeted claim failed to claim job';
  END IF;
END;
$$;

SELECT set_config('role', 'postgres', true);

SELECT is(
  (SELECT status FROM public.query_job WHERE job_kind = 'manual_refresh' LIMIT 1),
  'running',
  'targeted claim moves job status to running'
);

SELECT is(
  (SELECT status FROM public.query_execution WHERE provider_id = 'datajud_public' LIMIT 1),
  'running',
  'targeted claim creates execution in running status'
);

-- 7. Test complete_query_execution with datajud_public and observed result
SELECT lives_ok(
  $$
  DO $do$
  DECLARE
    v_job_id UUID;
    v_exec_id UUID;
    v_token UUID;
    v_norm JSONB;
    v_corr TEXT;
  BEGIN
    SELECT id, lease_token INTO v_job_id, v_token FROM public.query_job WHERE job_kind = 'manual_refresh' LIMIT 1;
    SELECT id, correlation_id INTO v_exec_id, v_corr FROM public.query_execution WHERE query_job_id = v_job_id LIMIT 1;

    v_norm := jsonb_build_object(
      'kind', 'observation',
      'status', 'observed',
      'source', 'datajud',
      'contractVersion', '1',
      'capability', 'process_observation',
      'correlationId', v_corr,
      'provider', jsonb_build_object('providerId', 'datajud_public', 'adapterVersion', '1.0.0'),
      'data', jsonb_build_object('processRef', '00044531220268160000', 'tribunal', 'TJPR'),
      'returnedFields', jsonb_build_array('processRef', 'tribunal'),
      'missingFields', jsonb_build_array('parties', 'system'),
      'sourceMetadata', jsonb_build_object('sourceType', 'datajud', 'sourceUpdatedAt', '2026-09-01T12:00:00Z'),
      'evidence', jsonb_build_object('evidenceType', 'provider_response', 'evidenceRef', 'datajud-public:abc')
    );

    PERFORM set_service_role();

    PERFORM * FROM public.phase9_complete_query_execution(
      v_job_id,
      v_exec_id,
      v_token,
      'observation',
      'observed',
      NULL,
      v_norm,
      NULL,
      NULL,
      now(),
      200,
      150,
      NULL
    );
  END
  $do$;
  $$,
  'phase9_complete_query_execution successfully completes manual_refresh with datajud_public'
);

SELECT set_config('role', 'postgres', true);

SELECT is(
  (SELECT status FROM public.query_job WHERE job_kind = 'manual_refresh' LIMIT 1),
  'succeeded',
  'completed execution transitions job to succeeded'
);

SELECT ok(
  EXISTS(SELECT 1 FROM public.process_snapshot WHERE provider_id = 'datajud_public'),
  'process_snapshot created for datajud_public observation'
);

-- 8. Test error code allowlist with datajud_multiple_hits_returned
SELECT lives_ok(
  $$
  DO $do$
  DECLARE
    v_proc_id UUID := '91000000-0000-4000-c000-000000000091';
    v_job_id UUID;
    v_exec_id UUID;
    v_token UUID;
    v_req RECORD;
  BEGIN
    -- Request another refresh
    PERFORM set_auth_user('91000000-0000-4000-8000-000000000091');
    SELECT * INTO v_req FROM public.realignment1_request_process_refresh(v_proc_id);
    v_job_id := v_req.job_id;

    -- Claim as service role
    PERFORM set_service_role();
    SELECT execution_id, lease_token INTO v_exec_id, v_token
      FROM public.realignment1_claim_query_job('worker-backend-2', v_job_id, 30000);

    -- Complete as failure with datajud_multiple_hits_returned
    PERFORM * FROM public.phase9_complete_query_execution(
      v_job_id,
      v_exec_id,
      v_token,
      'failure',
      'manual_review_required',
      'datajud_multiple_hits_returned',
      NULL,
      NULL,
      NULL,
      now(),
      200,
      120,
      NULL
    );
  END
  $do$;
  $$,
  'phase9_complete_query_execution accepts datajud_multiple_hits_returned error code'
);

SELECT set_config('role', 'postgres', true);

SELECT is(
  (SELECT status FROM public.query_job WHERE last_error_code = 'datajud_multiple_hits_returned'),
  'terminal_failure',
  'manual_review_required with multiple hits becomes terminal_failure on job'
);

SELECT * FROM finish();
ROLLBACK;
