BEGIN;

SELECT plan(13);

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

SELECT has_function(
  'public',
  'get_client_portfolio_grid',
  ARRAY['uuid', 'text', 'text', 'boolean'],
  'filtered portfolio grid function exists'
);

SELECT is(
  (
    SELECT p.prosecdef
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'get_client_portfolio_grid'
       AND p.proargtypes = '2950 25 25 16'::oidvector
  ),
  false,
  'filtered portfolio grid runs as invoker'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.get_client_portfolio_grid(uuid,text,text,boolean)',
    'EXECUTE'
  ),
  'authenticated can read the filtered portfolio grid'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.get_client_portfolio_grid(uuid,text,text,boolean)',
    'EXECUTE'
  ),
  'anon cannot read the filtered portfolio grid'
);

SET ROLE postgres;

INSERT INTO auth.users (id, email)
VALUES
  ('95000000-0000-4000-8000-000000000001', 'grid-lawyer@example.test'),
  ('95000000-0000-4000-8000-000000000002', 'grid-other@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('95000000-0000-4000-9000-000000000001', 'Grid Office', true),
  ('95000000-0000-4000-9000-000000000002', 'Grid Other Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = EXCLUDED.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES
  ('95000000-0000-4000-8000-000000000001', '95000000-0000-4000-9000-000000000001', 'Grid Lawyer', 'lawyer', true, true),
  ('95000000-0000-4000-8000-000000000002', '95000000-0000-4000-9000-000000000002', 'Other Grid Lawyer', 'lawyer', true, true)
ON CONFLICT (id) DO UPDATE SET
  office_id = EXCLUDED.office_id,
  is_active = EXCLUDED.is_active;

INSERT INTO public.party (
  id, office_id, party_type, display_name, normalized_name, created_by
)
VALUES
  ('95000000-0000-4000-a000-000000000001', '95000000-0000-4000-9000-000000000001', 'person', 'Cliente Grade', 'cliente grade', '95000000-0000-4000-8000-000000000001'),
  ('95000000-0000-4000-a000-000000000002', '95000000-0000-4000-9000-000000000002', 'person', 'Outro Cliente', 'outro cliente', '95000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES
  ('95000000-0000-4000-b000-000000000001', '95000000-0000-4000-9000-000000000001', '95000000-0000-4000-a000-000000000001', '95000000-0000-4000-8000-000000000001'),
  ('95000000-0000-4000-b000-000000000002', '95000000-0000-4000-9000-000000000002', '95000000-0000-4000-a000-000000000002', '95000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system,
  is_public, monitoring_status, status, created_by
)
VALUES
  ('95000000-0000-4000-c000-000000000001', '95000000-0000-4000-9000-000000000001', '95000000-0000-4000-b000-000000000001', '00044531220268160000', 'TJPR', 'PJe', true, 'paused', 'active', '95000000-0000-4000-8000-000000000001'),
  ('95000000-0000-4000-c000-000000000002', '95000000-0000-4000-9000-000000000001', '95000000-0000-4000-b000-000000000001', '00039075420268160000', 'TJPR', 'PJe', false, 'paused', 'active', '95000000-0000-4000-8000-000000000001'),
  ('95000000-0000-4000-c000-000000000003', '95000000-0000-4000-9000-000000000002', '95000000-0000-4000-b000-000000000002', '00085696120268160000', 'TJSP', 'PJe', true, 'paused', 'active', '95000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at, created_by,
  created_at, updated_at, finished_at
)
VALUES (
  '95000000-0000-4000-d000-000000000001', '95000000-0000-4000-9000-000000000001', '95000000-0000-4000-c000-000000000001', 'datajud_public', 'process_observation', 'manual_refresh', NULL, 'grid-observation', repeat('9', 64), 'grid-observation', 'succeeded', 1, 3, '2026-09-15 10:00:00+00', '95000000-0000-4000-8000-000000000001', '2026-09-15 10:00:00+00', '2026-09-15 10:00:01+00', '2026-09-15 10:00:01+00'
);

INSERT INTO public.provider_exchange (
  id, office_id, process_id, provider_id, source, contract_version,
  subject_ref, correlation_id, request_fingerprint, result_kind, result_status,
  normalized_result, created_at
)
VALUES (
  '95000000-0000-4000-e000-000000000001',
  '95000000-0000-4000-9000-000000000001',
  '95000000-0000-4000-c000-000000000001',
  'datajud_public',
  'datajud',
  1,
  '00044531220268160000',
  'grid-observation',
  repeat('9', 64),
  'observation',
  'observed',
  jsonb_build_object(
    'kind', 'observation',
    'status', 'observed',
    'provider', jsonb_build_object(
      'providerId', 'datajud_public',
      'providerKind', 'datajud',
      'adapterVersion', '1.0.0',
      'contractVersion', 1
    ),
    'source', 'datajud',
    'contractVersion', 1,
    'capability', 'process_observation',
    'correlationId', 'grid-observation',
    'data', jsonb_build_object(
      'processRef', '00044531220268160000',
      'tribunal', 'TJPR',
      'system', 'PJe',
      'basicData', jsonb_build_object(
        'filingDate', '2026-01-10T00:00:00Z',
        'degree', 'G1',
        'secrecyLevel', '0',
        'format', jsonb_build_object('code', '1', 'name', 'Eletrônico'),
        'system', jsonb_build_object('code', '1', 'name', 'PJe'),
        'processClass', jsonb_build_object('code', '1116', 'name', 'Ação cível'),
        'subjects', jsonb_build_array(),
        'court', jsonb_build_object('code', '100', 'name', '1ª Vara Cível')
      ),
      'movements', jsonb_build_array(
        jsonb_build_object(
          'movementRef', 'GRID-M-1',
          'code', '1',
          'type', 'Sentença',
          'date', '2026-09-15T09:00:00Z',
          'description', 'Sentença publicada no processo',
          'court', jsonb_build_object('code', '100', 'name', '1ª Vara Cível'),
          'missingFields', jsonb_build_array()
        )
      )
    ),
    'returnedFields', jsonb_build_array('processRef', 'tribunal', 'system', 'basicData', 'movements'),
    'missingFields', jsonb_build_array('parties'),
    'sourceMetadata', jsonb_build_object(
      'sourceType', 'datajud',
      'providerId', 'datajud_public',
      'adapterVersion', '1.0.0',
      'contractVersion', 1,
      'observedAt', '2026-09-15T10:00:01Z',
      'sourceUpdatedAt', '2026-09-15T09:00:00Z'
    ),
    'evidence', jsonb_build_object(
      'evidenceType', 'provider_response',
      'evidenceRef', 'grid-fixture',
      'observedAt', '2026-09-15T10:00:01Z'
    )
  ),
  '2026-09-15 10:00:01+00'
);

INSERT INTO public.query_execution (
  id, office_id, query_job_id, process_id, provider_id, capability,
  attempt_number, status, started_at, finished_at, duration_ms,
  provider_exchange_id, correlation_id, created_at
)
VALUES (
  '95000000-0000-4000-f000-000000000001',
  '95000000-0000-4000-9000-000000000001',
  '95000000-0000-4000-d000-000000000001',
  '95000000-0000-4000-c000-000000000001',
  'datajud_public',
  'process_observation',
  1,
  'succeeded',
  '2026-09-15 10:00:00+00',
  '2026-09-15 10:00:01+00',
  100,
  '95000000-0000-4000-e000-000000000001',
  'grid-observation:attempt:1',
  '2026-09-15 10:00:01+00'
);

SELECT * FROM pg_temp.set_auth_user('95000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT (grid ->> 'processCount')::INTEGER
     FROM public.get_client_portfolio_grid(
       '95000000-0000-4000-b000-000000000001', NULL, NULL, NULL
     ) AS grid),
  2,
  'client filter returns only the selected client'
);

SELECT is(
  (SELECT (grid ->> 'processCount')::INTEGER
     FROM public.get_client_portfolio_grid(
       '95000000-0000-4000-b000-000000000001', '0004453', NULL, NULL
     ) AS grid),
  1,
  'search matches the CNJ'
);

SELECT is(
  (SELECT (grid ->> 'processCount')::INTEGER
     FROM public.get_client_portfolio_grid(
       NULL, 'cliente grade', NULL, NULL
     ) AS grid),
  2,
  'search matches the client name'
);

SELECT is(
  (SELECT (grid ->> 'processCount')::INTEGER
     FROM public.get_client_portfolio_grid(
       NULL, 'sentença publicada', NULL, NULL
     ) AS grid),
  1,
  'search matches the movement description'
);

SELECT is(
  (SELECT process -> 'lastMovement' ->> 'type'
     FROM public.get_client_portfolio_grid(
       '95000000-0000-4000-b000-000000000001', NULL, NULL, NULL
     ) AS grid
     CROSS JOIN LATERAL jsonb_array_elements(grid -> 'processes') AS process
    WHERE process ->> 'cnjNumber' = '00044531220268160000'),
  'Sentença',
  'movement type remains a separate read model field'
);

SELECT is(
  (SELECT (grid ->> 'processCount')::INTEGER
     FROM public.get_client_portfolio_grid(
       '95000000-0000-4000-b000-000000000001', NULL, 'not_consulted', NULL
     ) AS grid),
  1,
  'state filter returns only not consulted processes'
);

SELECT is(
  (SELECT (grid ->> 'processCount')::INTEGER
     FROM public.get_client_portfolio_grid(
       '95000000-0000-4000-b000-000000000001', NULL, NULL, false
     ) AS grid),
  1,
  'visibility filter returns only sealed processes'
);

SELECT is(
  (SELECT count(*)::INTEGER
     FROM public.get_client_portfolio_grid(
       '95000000-0000-4000-b000-000000000002', NULL, NULL, NULL
     )),
  0,
  'another office cannot read the selected client'
);

SELECT is(
  (SELECT count(*)::INTEGER
     FROM public.get_client_portfolio_grid(NULL, NULL, NULL, NULL)),
  1,
  'RLS limits the unscoped grid to the current office'
);

SELECT * FROM finish();
ROLLBACK;
