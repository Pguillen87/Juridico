BEGIN;

SELECT plan(27);

CREATE OR REPLACE FUNCTION pg_temp.set_auth_user(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', p_user_id::TEXT, true);
  PERFORM set_config(
    'request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', p_user_id),
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_service_role()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'service_role', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
END;
$$;

SELECT has_table(
  'public', 'process_refresh_batch',
  'process refresh batch table exists'
);

SELECT has_function(
  'public',
  'realignment1_request_client_portfolio_refresh',
  ARRAY['uuid'],
  'portfolio batch request function exists'
);

SELECT is_definer(
  'public',
  'realignment1_request_client_portfolio_refresh',
  ARRAY['uuid']
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.realignment1_request_client_portfolio_refresh(uuid)',
    'EXECUTE'
  ),
  'authenticated can request a portfolio batch'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.realignment1_request_client_portfolio_refresh(uuid)',
    'EXECUTE'
  ),
  'anon cannot request a portfolio batch'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.realignment1_claim_client_portfolio_job(uuid,text,integer)',
    'EXECUTE'
  ),
  'authenticated cannot claim portfolio jobs'
);

SELECT ok(
  has_function_privilege(
    'service_role',
    'public.realignment1_claim_client_portfolio_job(uuid,text,integer)',
    'EXECUTE'
  ),
  'service_role can claim portfolio jobs'
);

SET ROLE postgres;

INSERT INTO auth.users (id, email)
VALUES
  ('93000000-0000-4000-8000-000000000001', 'batch-lawyer@example.test'),
  ('93000000-0000-4000-8000-000000000002', 'batch-other@example.test'),
  ('93000000-0000-4000-8000-000000000003', 'batch-backup@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('93000000-0000-4000-9000-000000000001', 'Batch Office', true),
  ('93000000-0000-4000-9000-000000000002', 'Batch Other Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = EXCLUDED.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES
  ('93000000-0000-4000-8000-000000000001', '93000000-0000-4000-9000-000000000001', 'Batch Lawyer', 'lawyer', true, true),
  ('93000000-0000-4000-8000-000000000002', '93000000-0000-4000-9000-000000000002', 'Other Lawyer', 'lawyer', true, true),
  ('93000000-0000-4000-8000-000000000003', '93000000-0000-4000-9000-000000000001', 'Batch Backup Owner', 'lawyer', true, true)
ON CONFLICT (id) DO UPDATE SET office_id = EXCLUDED.office_id, is_active = EXCLUDED.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES
  ('93000000-0000-4000-a000-000000000001', '93000000-0000-4000-9000-000000000001', 'person', 'Batch Client', 'batch client', '93000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-a000-000000000002', '93000000-0000-4000-9000-000000000002', 'person', 'Other Client', 'other client', '93000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES
  ('93000000-0000-4000-b000-000000000001', '93000000-0000-4000-9000-000000000001', '93000000-0000-4000-a000-000000000001', '93000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-b000-000000000002', '93000000-0000-4000-9000-000000000002', '93000000-0000-4000-a000-000000000002', '93000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system,
  is_public, monitoring_status, status, created_by
) VALUES
  ('93000000-0000-4000-c000-000000000001', '93000000-0000-4000-9000-000000000001', '93000000-0000-4000-b000-000000000001', '00044531220268160000', 'TJPR', 'PJe', true, 'paused', 'active', '93000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-c000-000000000002', '93000000-0000-4000-9000-000000000001', '93000000-0000-4000-b000-000000000001', '00039075420268160000', 'TJPR', 'PJe', false, 'paused', 'active', '93000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-c000-000000000003', '93000000-0000-4000-9000-000000000001', '93000000-0000-4000-b000-000000000001', '00085696120268160000', 'TJPR', 'PJe', true, 'paused', 'inactive', '93000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

SELECT * FROM pg_temp.set_auth_user('93000000-0000-4000-8000-000000000001');

CREATE TEMP TABLE pg_temp.batch_request_result ON COMMIT DROP AS
SELECT *
  FROM public.realignment1_request_client_portfolio_refresh(
    '93000000-0000-4000-b000-000000000001'
  );

SELECT is(
  (SELECT state FROM pg_temp.batch_request_result),
  'queued',
  'batch request is queued when an eligible process exists'
);

SELECT is(
  (SELECT eligible_count FROM pg_temp.batch_request_result),
  1,
  'only active public processes are eligible'
);

SELECT is(
  (SELECT skipped_count FROM pg_temp.batch_request_result),
  2,
  'sealed and inactive processes are skipped'
);

SELECT is(
  (SELECT count(*)::INTEGER FROM public.process_refresh_batch),
  1,
  'one parent batch is created'
);

SELECT is(
  (SELECT count(*)::INTEGER FROM public.query_job WHERE batch_id IS NOT NULL),
  1,
  'one child job is created for the eligible process'
);

SELECT is(
  (SELECT process_id FROM public.query_job WHERE batch_id IS NOT NULL),
  '93000000-0000-4000-c000-000000000001'::UUID,
  'child job belongs to the eligible process'
);

SELECT is(
  (SELECT count(*)::INTEGER FROM public.query_job WHERE process_id IN (
    '93000000-0000-4000-c000-000000000002'::UUID,
    '93000000-0000-4000-c000-000000000003'::UUID
  )),
  0,
  'skipped processes do not receive child jobs'
);

SET ROLE postgres;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_log
     WHERE action = 'process_refresh_batch.requested'
       AND entity_type = 'process_refresh_batch'
       AND actor_user_id = '93000000-0000-4000-8000-000000000001'
  ),
  'batch request is audited with the active actor'
);

SELECT * FROM pg_temp.set_auth_user('93000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT state
     FROM public.realignment1_request_client_portfolio_refresh(
       '93000000-0000-4000-b000-000000000001'
     )),
  'already_running',
  'an active batch is idempotent'
);

SELECT is(
  (SELECT count(*)::INTEGER FROM public.process_refresh_batch),
  1,
  'idempotent request does not create a second active batch'
);

SELECT is(
  (public.get_client_portfolio_refresh_progress(
    '93000000-0000-4000-b000-000000000001'
  )->>'state'),
  'queued',
  'progress reports queued state'
);

SELECT is(
  (public.get_client_portfolio_refresh_progress(
    '93000000-0000-4000-b000-000000000001'
  )->>'eligibleCount')::INTEGER,
  1,
  'progress reports eligible count'
);

SELECT is(
  (public.get_client_portfolio_refresh_progress(
    '93000000-0000-4000-b000-000000000001'
  )->>'pendingCount')::INTEGER,
  1,
  'progress reports pending child job'
);

SELECT is(
  public.get_client_portfolio_refresh_progress(
    '93000000-0000-4000-b000-000000000002'
  ),
  NULL::JSONB,
  'progress does not leak another office'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
      FROM public.query_job qj
     WHERE qj.batch_id IS NOT NULL
       AND qj.process_id IN (
         '93000000-0000-4000-c000-000000000002'::UUID,
         '93000000-0000-4000-c000-000000000003'::UUID
       )
  ),
  'batch child selection is limited to public active processes'
);

SET ROLE service_role;

CREATE TEMP TABLE pg_temp.claim_result ON COMMIT DROP AS
SELECT *
  FROM public.realignment1_claim_client_portfolio_job(
    (SELECT id
       FROM public.process_refresh_batch
      WHERE client_id = '93000000-0000-4000-b000-000000000001'::UUID
      ORDER BY created_at
      LIMIT 1),
    'batch-worker-test',
    30000
  );

SET ROLE postgres;

SELECT is(
  (SELECT process_id FROM pg_temp.claim_result),
  '93000000-0000-4000-c000-000000000001'::UUID,
  'backend claim stays inside the requested batch'
);

SELECT is(
  (SELECT status
     FROM public.query_job
    WHERE batch_id IS NOT NULL
      AND process_id = '93000000-0000-4000-c000-000000000001'::UUID),
  'running',
  'batch claim moves the child job to running'
);

SELECT is(
  (SELECT count(*)::INTEGER FROM public.query_execution WHERE query_job_id = (SELECT job_id FROM pg_temp.claim_result)),
  1,
  'batch claim creates one execution'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.audit_log
     WHERE action = 'query_job.claimed'
       AND entity_type = 'query_job'
  ),
  'batch claim preserves operational audit'
);

SET ROLE postgres;
UPDATE public.user_profile
   SET is_active = false
 WHERE id = '93000000-0000-4000-8000-000000000001';

SELECT * FROM pg_temp.set_auth_user('93000000-0000-4000-8000-000000000001');

SELECT throws_ok(
  $$SELECT * FROM public.realignment1_request_client_portfolio_refresh('93000000-0000-4000-b000-000000000001')$$,
  '42501',
  NULL,
  'inactive user cannot request a portfolio batch'
);

SELECT * FROM finish();
ROLLBACK;
