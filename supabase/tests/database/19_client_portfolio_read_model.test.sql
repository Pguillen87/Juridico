BEGIN;

SELECT plan(21);

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

CREATE OR REPLACE FUNCTION pg_temp.seed_portfolio_observation(
  p_office_id UUID,
  p_process_id UUID,
  p_cnj TEXT,
  p_job_id UUID,
  p_execution_id UUID,
  p_exchange_id UUID,
  p_snapshot_id UUID,
  p_correlation_id TEXT,
  p_fingerprint TEXT,
  p_created_at TIMESTAMPTZ,
  p_description TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_data JSONB;
  v_normalized_result JSONB;
BEGIN
  v_data := jsonb_build_object(
    'processRef', p_cnj,
    'tribunal', 'TJ-SYNTHETIC',
    'system', 'synthetic-system',
    'movements', jsonb_build_array(
      jsonb_build_object(
        'movementRef', 'M-1',
        'date', to_char(p_created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'description', p_description,
        'missingFields', '[]'::JSONB
      )
    ),
    'parties', jsonb_build_array(
      jsonb_build_object(
        'partyRef', 'P-1',
        'role', 'plaintiff',
        'missingFields', '[]'::JSONB
      )
    )
  );

  v_normalized_result := jsonb_build_object(
    'kind', 'observation',
    'status', 'observed',
    'source', 'datajud',
    'contractVersion', '1',
    'capability', 'process_observation',
    'correlationId', p_correlation_id,
    'provider', jsonb_build_object(
      'providerId', 'datajud_public',
      'adapterVersion', '1.0.0'
    ),
    'data', v_data,
    'returnedFields', jsonb_build_array('processRef', 'tribunal', 'system', 'movements', 'parties'),
    'missingFields', '[]'::JSONB,
    'sourceMetadata', jsonb_build_object(
      'sourceType', 'datajud',
      'sourceUpdatedAt', p_created_at::TEXT
    ),
    'evidence', jsonb_build_object(
      'evidenceType', 'provider_response',
      'evidenceRef', 'portfolio-fixture:' || p_correlation_id
    )
  );

  INSERT INTO public.query_job (
    id, office_id, process_id, provider_id, capability, job_kind,
    scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
    status, attempt_count, max_attempts, available_at, created_by,
    created_at, updated_at, finished_at
  ) VALUES (
    p_job_id, p_office_id, p_process_id, 'datajud_public', 'process_observation', 'manual_refresh',
    NULL, 'portfolio:' || p_correlation_id, p_fingerprint, p_correlation_id,
    'succeeded', 1, 3, p_created_at, NULL,
    p_created_at, p_created_at, p_created_at + INTERVAL '1 second'
  );

  INSERT INTO public.provider_exchange (
    id, office_id, process_id, provider_id, source, contract_version,
    subject_ref, correlation_id, request_fingerprint, result_kind, result_status,
    normalized_result, created_at
  ) VALUES (
    p_exchange_id, p_office_id, p_process_id, 'datajud_public', 'datajud', 1,
    p_cnj, p_correlation_id, p_fingerprint, 'observation', 'observed',
    v_normalized_result, p_created_at
  );

  INSERT INTO public.query_execution (
    id, office_id, query_job_id, process_id, provider_id, capability,
    attempt_number, status, started_at, finished_at, duration_ms,
    provider_exchange_id, correlation_id, created_at
  ) VALUES (
    p_execution_id, p_office_id, p_job_id, p_process_id, 'datajud_public', 'process_observation',
    1, 'succeeded', p_created_at, p_created_at + INTERVAL '1 second', 100,
    p_exchange_id, p_correlation_id || ':attempt:1', p_created_at
  );

  INSERT INTO public.process_snapshot (
    id, office_id, process_id, query_execution_id, provider_id, source,
    normalizer_version, normalized_data, missing_fields, snapshot_hash, created_at
  ) VALUES (
    p_snapshot_id, p_office_id, p_process_id, p_execution_id, 'datajud_public', 'datajud',
    '1.0.0', v_data, '[]'::JSONB,
    encode(extensions.digest(convert_to(v_data::TEXT, 'UTF8'), 'sha256'), 'hex'),
    p_created_at
  );
END;
$$;

SELECT has_function(
  'public',
  'get_client_portfolio_read_model',
  ARRAY['uuid'],
  'client portfolio read model function exists'
);

SELECT is(
  (
    SELECT p.prosecdef
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'get_client_portfolio_read_model'
       AND p.proargtypes = '2950'::oidvector
  ),
  false,
  'portfolio read model runs as invoker'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.get_client_portfolio_read_model(uuid)',
    'EXECUTE'
  ),
  'authenticated can read the client portfolio'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.get_client_portfolio_read_model(uuid)',
    'EXECUTE'
  ),
  'anon cannot read the client portfolio'
);

SET ROLE postgres;

INSERT INTO auth.users (id, email)
VALUES
  ('92000000-0000-4000-8000-000000000001', 'portfolio-lawyer@example.test'),
  ('92000000-0000-4000-8000-000000000002', 'portfolio-other-office@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('92000000-0000-4000-9000-000000000001', 'Portfolio Office', true),
  ('92000000-0000-4000-9000-000000000002', 'Portfolio Other Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = EXCLUDED.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES
  ('92000000-0000-4000-8000-000000000001', '92000000-0000-4000-9000-000000000001', 'Portfolio Lawyer', 'lawyer', false, true),
  ('92000000-0000-4000-8000-000000000002', '92000000-0000-4000-9000-000000000002', 'Other Office Lawyer', 'lawyer', false, true)
ON CONFLICT (id) DO UPDATE SET
  office_id = EXCLUDED.office_id,
  role = EXCLUDED.role,
  is_owner = EXCLUDED.is_owner,
  is_active = EXCLUDED.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES
  ('92000000-0000-4000-a000-000000000001', '92000000-0000-4000-9000-000000000001', 'person', 'Portfolio Client', 'portfolio client', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-a000-000000000002', '92000000-0000-4000-9000-000000000002', 'person', 'Other Office Client', 'other office client', '92000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES
  ('92000000-0000-4000-b000-000000000001', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-a000-000000000001', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-b000-000000000002', '92000000-0000-4000-9000-000000000002', '92000000-0000-4000-a000-000000000002', '92000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
) VALUES
  ('92000000-0000-4000-c000-000000000001', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-b000-000000000001', '00025573120268160000', 'TJ-SYNTHETIC', 'Portfolio', true, 'active', 'active', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-c000-000000000002', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-b000-000000000001', '00039075420268160000', 'TJ-SYNTHETIC', 'Portfolio', true, 'active', 'active', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-c000-000000000003', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-b000-000000000001', '00044531220268160000', 'TJ-SYNTHETIC', 'Portfolio', true, 'active', 'active', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-c000-000000000004', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-b000-000000000001', '00085696120268160000', 'TJ-SYNTHETIC', 'Portfolio', true, 'active', 'active', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-c000-000000000005', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-b000-000000000001', '00044531220268160001', 'TJ-SYNTHETIC', 'Portfolio', true, 'active', 'active', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-c000-000000000006', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-b000-000000000001', '10000000000000000001', 'TJ-SYNTHETIC', 'Portfolio', true, 'active', 'active', '92000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-c000-000000000007', '92000000-0000-4000-9000-000000000002', '92000000-0000-4000-b000-000000000002', '20000000000000000003', 'TJ-SYNTHETIC', 'Other', true, 'active', 'active', '92000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at, last_error_code,
  last_error_message, created_by, created_at, updated_at, finished_at
) VALUES
  ('92000000-0000-4000-d000-000000000004', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-c000-000000000004', 'datajud_public', 'process_observation', 'manual_refresh', NULL, 'portfolio-failure', repeat('4', 64), 'portfolio-failure', 'terminal_failure', 1, 3, '2026-09-10 10:00:00+00', 'datajud_source_unavailable', 'synthetic failure', '92000000-0000-4000-8000-000000000001', '2026-09-10 10:00:00+00', '2026-09-10 10:00:01+00', '2026-09-10 10:00:01+00'),
  ('92000000-0000-4000-d000-000000000005', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-c000-000000000005', 'datajud_public', 'process_observation', 'manual_refresh', NULL, 'portfolio-review', repeat('5', 64), 'portfolio-review', 'terminal_failure', 1, 3, '2026-09-11 10:00:00+00', 'datajud_multiple_hits_returned', 'synthetic ambiguity', '92000000-0000-4000-8000-000000000001', '2026-09-11 10:00:00+00', '2026-09-11 10:00:01+00', '2026-09-11 10:00:01+00'),
  ('92000000-0000-4000-d000-000000000006', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-c000-000000000006', 'datajud_public', 'process_observation', 'manual_refresh', NULL, 'portfolio-updating', repeat('6', 64), 'portfolio-updating', 'pending', 0, 3, '2026-09-12 10:00:00+00', NULL, NULL, '92000000-0000-4000-8000-000000000001', '2026-09-12 10:00:00+00', '2026-09-12 10:00:00+00', NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_execution (
  id, office_id, query_job_id, process_id, provider_id, capability,
  attempt_number, status, started_at, finished_at, duration_ms,
  error_code, error_message_sanitized, correlation_id, created_at
) VALUES
  ('92000000-0000-4000-f000-000000000004', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-d000-000000000004', '92000000-0000-4000-c000-000000000004', 'datajud_public', 'process_observation', 1, 'terminal_failure', '2026-09-10 10:00:00+00', '2026-09-10 10:00:01+00', 100, 'datajud_source_unavailable', 'A consulta não produziu uma observação válida.', 'portfolio-failure:attempt:1', '2026-09-10 10:00:00+00'),
  ('92000000-0000-4000-f000-000000000005', '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-d000-000000000005', '92000000-0000-4000-c000-000000000005', 'datajud_public', 'process_observation', 1, 'terminal_failure', '2026-09-11 10:00:00+00', '2026-09-11 10:00:01+00', 100, 'datajud_multiple_hits_returned', 'A consulta não produziu uma observação válida.', 'portfolio-review:attempt:1', '2026-09-11 10:00:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.provider_exchange (
  id, office_id, process_id, provider_id, source, contract_version,
  subject_ref, correlation_id, request_fingerprint, result_kind, result_status,
  error_code, normalized_result, created_at
) VALUES (
  '92000000-0000-4000-e000-000000000005',
  '92000000-0000-4000-9000-000000000001',
  '92000000-0000-4000-c000-000000000005',
  'datajud_public', 'datajud', 1,
  '00044531220268160001', 'portfolio-review:attempt:1', repeat('5', 64),
  'failure', 'manual_review_required', 'datajud_multiple_hits_returned', NULL,
  '2026-09-11 10:00:01+00'
)
ON CONFLICT (id) DO NOTHING;

SELECT pg_temp.seed_portfolio_observation(
  '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-c000-000000000002', '00039075420268160000',
  '92000000-0000-4000-d000-000000000002', '92000000-0000-4000-f000-000000000002', '92000000-0000-4000-e000-000000000002', '92000000-0000-4000-1000-000000000002',
  'portfolio-first', repeat('2', 64), '2026-09-08 10:00:00+00', 'Primeiro movimento'
);

SELECT pg_temp.seed_portfolio_observation(
  '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-c000-000000000003', '00044531220268160000',
  '92000000-0000-4000-d000-000000000031', '92000000-0000-4000-f000-000000000031', '92000000-0000-4000-e000-000000000031', '92000000-0000-4000-1000-000000000031',
  'portfolio-changed-1', repeat('3', 64), '2026-09-09 10:00:00+00', 'Movimento anterior'
);

SELECT pg_temp.seed_portfolio_observation(
  '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-c000-000000000003', '00044531220268160000',
  '92000000-0000-4000-d000-000000000032', '92000000-0000-4000-f000-000000000032', '92000000-0000-4000-e000-000000000032', '92000000-0000-4000-1000-000000000032',
  'portfolio-changed-2', repeat('a', 64), '2026-09-09 11:00:00+00', 'Movimento novo'
);

SET ROLE service_role;

SELECT * FROM public.phase10_compare_process_snapshot_v2(
  '92000000-0000-4000-1000-000000000002', 'comparison-v1', 'not_comparable', 'first_snapshot',
  '[]'::JSONB, '{"entries":[]}'::JSONB
);

SELECT * FROM public.phase10_compare_process_snapshot_v2(
  '92000000-0000-4000-1000-000000000031', 'comparison-v1', 'not_comparable', 'first_snapshot',
  '[]'::JSONB, '{"entries":[]}'::JSONB
);

SELECT * FROM public.phase10_compare_process_snapshot_v2(
  '92000000-0000-4000-1000-000000000032', 'comparison-v1', 'changed', NULL,
  '["/movements/by-ref/M-1/description"]'::JSONB,
  '{"entries":[{"path":"/movements/by-ref/M-1/description","changeType":"movement_updated","before":"Movimento anterior","after":"Movimento novo"}]}'::JSONB
);

RESET ROLE;
SELECT * FROM pg_temp.set_auth_user('92000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT (portfolio ->> 'processCount')::INTEGER
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio),
  6,
  'cliente recebe a quantidade correta de processos vinculados'
);

SELECT is(
  (SELECT jsonb_array_length(portfolio -> 'processes')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio),
  6,
  'lista contém somente os processos do cliente'
);

SELECT is(
  (SELECT (process ->> 'state')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000001'),
  'not_consulted',
  'processo sem consulta aparece como não consultado'
);

SELECT is(
  (SELECT (portfolio ->> 'notUpdatedCount')::INTEGER
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio),
  1,
  'contagem de processos ainda não consultados é derivada do read model'
);

SELECT is(
  (SELECT (process ->> 'state')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000002'),
  'first_observation',
  'primeira consulta aparece como primeira observação'
);

SELECT is(
  (SELECT (process ->> 'newMovementCount')::INTEGER
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000002'),
  1,
  'primeira consulta informa a quantidade de movimentações disponíveis'
);

SELECT is(
  (SELECT (process ->> 'state')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000003'),
  'changed',
  'comparação mais recente alterada produz estado com novidade'
);

SELECT is(
  (SELECT (portfolio ->> 'noveltyCount')::INTEGER
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio),
  1,
  'novidade é contada no cliente somente para a comparação mais recente'
);

SELECT is(
  (SELECT (process ->> 'state')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000004'),
  'failure',
  'falha não aparece como sem novidade'
);

SELECT is(
  (SELECT (process ->> 'state')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000005'),
  'manual_review',
  'ambiguidade da fonte aparece como revisão manual'
);

SELECT is(
  (SELECT (process ->> 'state')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000006'),
  'updating',
  'job pendente aparece como atualização em andamento'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
      FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
           jsonb_array_elements(portfolio -> 'processes') AS process
     WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000007'
  ),
  'outro office não aparece na carteira'
);

SELECT is(
  (SELECT (process ->> 'sourceUpdatedAt')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000002'),
  '2026-09-08 10:00:00+00',
  'última atualização da fonte vem do metadado normalizado'
);

SET ROLE postgres;

SELECT pg_temp.seed_portfolio_observation(
  '92000000-0000-4000-9000-000000000001', '92000000-0000-4000-c000-000000000003', '00044531220268160000',
  '92000000-0000-4000-d000-000000000033', '92000000-0000-4000-f000-000000000033', '92000000-0000-4000-e000-000000000033', '92000000-0000-4000-1000-000000000033',
  'portfolio-unchanged', repeat('b', 64), '2026-09-09 12:00:00+00', 'Movimento novo'
);

SET ROLE service_role;

SELECT * FROM public.phase10_compare_process_snapshot_v2(
  '92000000-0000-4000-1000-000000000033', 'comparison-v1', 'unchanged', NULL,
  '[]'::JSONB, '{"entries":[]}'::JSONB
);

RESET ROLE;
SELECT * FROM pg_temp.set_auth_user('92000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT (process ->> 'state')
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio,
          jsonb_array_elements(portfolio -> 'processes') AS process
    WHERE process ->> 'processId' = '92000000-0000-4000-c000-000000000003'),
  'unchanged',
  'consulta posterior sem mudança encerra a novidade anterior'
);

SELECT is(
  (SELECT (portfolio ->> 'noveltyCount')::INTEGER
     FROM public.get_client_portfolio_read_model('92000000-0000-4000-b000-000000000001') AS portfolio),
  0,
  'mudança antiga não permanece como novidade após consulta sem mudança'
);

SET ROLE postgres;
UPDATE public.user_profile
   SET is_active = false
 WHERE id = '92000000-0000-4000-8000-000000000001';

SELECT * FROM pg_temp.set_auth_user('92000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT count(*)::INTEGER FROM public.get_client_portfolio_read_model(NULL)),
  0,
  'usuário inativo permanece bloqueado pelo D-022/RLS'
);

SET ROLE postgres;
UPDATE public.user_profile
   SET is_active = true
 WHERE id = '92000000-0000-4000-8000-000000000001';
UPDATE public.office
   SET is_active = false
 WHERE id = '92000000-0000-4000-9000-000000000001';

SELECT * FROM pg_temp.set_auth_user('92000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT count(*)::INTEGER FROM public.get_client_portfolio_read_model(NULL)),
  0,
  'office inativo permanece bloqueado pelo D-022/RLS'
);

SELECT * FROM finish();
ROLLBACK;
