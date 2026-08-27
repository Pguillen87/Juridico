INSERT INTO auth.users (id, email)
VALUES ('a1000000-0000-4000-8000-000000000001', 'phase10-lawyer@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES ('a1000000-0000-4000-9000-000000000001', 'Phase 10 Synthetic Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = excluded.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES (
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'Phase 10 Lawyer', 'lawyer', false, true
)
ON CONFLICT (id) DO UPDATE SET office_id = excluded.office_id, role = excluded.role,
  is_owner = excluded.is_owner, is_active = excluded.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES (
  'a1000000-0000-4000-a000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'person', 'Phase 10 Synthetic Party', 'phase 10 synthetic party',
  'a1000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES (
  'a1000000-0000-4000-b000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-a000-000000000001', 'active',
  'a1000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
) VALUES (
  'a1000000-0000-4000-c000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-b000-000000000001',
  '10000000000000000001', 'TJ-SYNTHETIC', 'synthetic-system', true,
  'active', 'active', 'a1000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO UPDATE SET is_public = excluded.is_public,
  monitoring_status = excluded.monitoring_status, status = excluded.status;

INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at, finished_at
) VALUES
(
  'a1000000-0000-4000-d000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-26 10:00:00+00',
  'phase10-job-1', repeat('1', 64), 'f10-exec-1', 'succeeded', 1, 3,
  '2026-08-26 10:00:00+00', '2026-08-26 10:00:01+00'
),
(
  'a1000000-0000-4000-d000-000000000002',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-26 10:01:00+00',
  'phase10-job-2', repeat('2', 64), 'f10-exec-2', 'succeeded', 1, 3,
  '2026-08-26 10:01:00+00', '2026-08-26 10:01:01+00'
),
(
  'a1000000-0000-4000-d000-000000000003',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-26 10:02:00+00',
  'phase10-job-3', repeat('3', 64), 'f10-exec-3', 'succeeded', 1, 3,
  '2026-08-26 10:02:00+00', '2026-08-26 10:02:01+00'
),
(
  'a1000000-0000-4000-d000-000000000004',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-26 10:03:00+00',
  'phase10-job-4', repeat('4', 64), 'f10-exec-4', 'succeeded', 1, 3,
  '2026-08-26 10:03:00+00', '2026-08-26 10:03:01+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.provider_exchange (
  id, office_id, process_id, provider_id, source, contract_version,
  subject_ref, correlation_id, request_fingerprint, result_kind, result_status,
  normalized_result
) VALUES
(
  'a1000000-0000-4000-e000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '10000000000000000001', 'f10-exec-1', repeat('1', 64), 'observation', 'observed', '{}'
),
(
  'a1000000-0000-4000-e000-000000000002',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '10000000000000000001', 'f10-exec-2', repeat('2', 64), 'observation', 'observed', '{}'
),
(
  'a1000000-0000-4000-e000-000000000003',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '10000000000000000001', 'f10-exec-3', repeat('3', 64), 'observation', 'observed', '{}'
),
(
  'a1000000-0000-4000-e000-000000000004',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '10000000000000000001', 'f10-exec-4', repeat('4', 64), 'observation', 'observed', '{}'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_execution (
  id, office_id, query_job_id, process_id, provider_id, capability,
  attempt_number, status, started_at, finished_at, duration_ms,
  provider_exchange_id, correlation_id
) VALUES
(
  'a1000000-0000-4000-f000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-d000-000000000001',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-26 10:00:00+00', '2026-08-26 10:00:01+00', 10,
  'a1000000-0000-4000-e000-000000000001', 'f10-exec-1'
),
(
  'a1000000-0000-4000-f000-000000000002',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-d000-000000000002',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-26 10:01:00+00', '2026-08-26 10:01:01+00', 10,
  'a1000000-0000-4000-e000-000000000002', 'f10-exec-2'
),
(
  'a1000000-0000-4000-f000-000000000003',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-d000-000000000003',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-26 10:02:00+00', '2026-08-26 10:02:01+00', 10,
  'a1000000-0000-4000-e000-000000000003', 'f10-exec-3'
),
(
  'a1000000-0000-4000-f000-000000000004',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-d000-000000000004',
  'a1000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-26 10:03:00+00', '2026-08-26 10:03:01+00', 10,
  'a1000000-0000-4000-e000-000000000004', 'f10-exec-4'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.process_snapshot (
  id, office_id, process_id, query_execution_id, provider_id, source,
  normalizer_version, normalized_data, missing_fields, snapshot_hash, created_at
) VALUES
(
  'a1000000-0000-4000-1000-000000000001',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001',
  'a1000000-0000-4000-f000-000000000001', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento antigo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento antigo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-26 10:00:00+00'
),
(
  'a1000000-0000-4000-1000-000000000002',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001',
  'a1000000-0000-4000-f000-000000000002', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system-v2","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento novo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system-v2","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento novo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-26 10:01:00+00'
),
(
  'a1000000-0000-4000-1000-000000000003',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001',
  'a1000000-0000-4000-f000-000000000003', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system-v2","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento novo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system-v2","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento novo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-26 10:02:00+00'
),
(
  'a1000000-0000-4000-1000-000000000004',
  'a1000000-0000-4000-9000-000000000001',
  'a1000000-0000-4000-c000-000000000001',
  'a1000000-0000-4000-f000-000000000004', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system-v2","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento novo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"10000000000000000001","tribunal":"TJ-SYNTHETIC","system":"synthetic-system-v2","movements":[{"movementRef":"M-1","date":"2026-01-01T00:00:00Z","description":"Movimento novo","missingFields":[]}],"parties":[{"partyRef":"P-1","role":"plaintiff","missingFields":[]}]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-26 10:03:00+00'
)
ON CONFLICT (id) DO NOTHING;

SELECT plan(33);

SELECT is((SELECT count(*)::integer
             FROM pg_class
            WHERE relname IN ('process_comparison', 'detected_change')
              AND relrowsecurity), 2, 'novas tabelas comparativas têm RLS habilitada');
SELECT ok(NOT has_table_privilege('authenticated', 'public.process_comparison', 'INSERT'), 'authenticated não insere comparação diretamente');
SELECT ok(NOT has_table_privilege('service_role', 'public.process_comparison', 'INSERT'), 'service_role não recebe INSERT direto em comparação');
SELECT ok(NOT has_function_privilege('public', 'public.phase10_compare_process_snapshot_v2(uuid,text,text,text,jsonb,jsonb)'::regprocedure, 'EXECUTE'), 'PUBLIC não executa comparação');
SELECT ok(NOT has_function_privilege('anon', 'public.phase10_compare_process_snapshot_v2(uuid,text,text,text,jsonb,jsonb)'::regprocedure, 'EXECUTE'), 'anon não executa comparação');
SELECT ok(NOT has_function_privilege('authenticated', 'public.phase10_compare_process_snapshot_v2(uuid,text,text,text,jsonb,jsonb)'::regprocedure, 'EXECUTE'), 'authenticated não executa comparação');
SELECT ok(has_function_privilege('service_role', 'public.phase10_compare_process_snapshot_v2(uuid,text,text,text,jsonb,jsonb)'::regprocedure, 'EXECUTE'), 'service_role executa comparação v2 backend-only');
SELECT ok(NOT has_function_privilege('service_role', 'public.phase10_get_snapshot_pair_internal(uuid)'::regprocedure, 'EXECUTE'), 'caminho legado do leitor não é executável');
SELECT ok(NOT has_function_privilege('service_role', 'public.phase10_compare_process_snapshot(uuid,text,text,text,jsonb,jsonb)'::regprocedure, 'EXECUTE'), 'caminho legado da comparação não é executável');

SET ROLE service_role;
SELECT * FROM public.phase10_compare_process_snapshot_v2(
  'a1000000-0000-4000-1000-000000000001', 'comparison-v1', 'not_comparable',
  'first_snapshot', '[]', '{"entries":[]}'
) \gset first_
SELECT is(:'first_result'::text, 'not_comparable'::text, 'primeiro snapshot é not_comparable');
SELECT is(:'first_replayed'::text, 'f'::text, 'primeira comparação não é replay');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.process_comparison WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 1, 'primeiro snapshot cria uma comparação');
SELECT is((SELECT count(*)::integer FROM public.detected_change WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 0, 'primeiro snapshot não cria detected_change');
SET ROLE service_role;

SELECT * FROM public.phase10_compare_process_snapshot_v2(
  'a1000000-0000-4000-1000-000000000002', 'comparison-v1', 'changed', NULL,
  '["/system", "/movements/by-ref/M-1/description"]',
  '{"entries":[{"path":"/system","changeType":"field_updated","before":"synthetic-system","after":"synthetic-system-v2"},{"path":"/movements/by-ref/M-1/description","changeType":"movement_updated","before":"Movimento antigo","after":"Movimento novo"}]}'
) \gset changed_
SELECT is(:'changed_result'::text, 'changed'::text, 'snapshot diferente produz changed');
SELECT ok(:'changed_detected_change_id' IS NOT NULL, 'changed cria detected_change');
SELECT ok(
  :'changed_changed_fields'::jsonb = '["/system", "/movements/by-ref/M-1/description"]'::jsonb,
  'RPC devolve changed_fields persistido sem alterar a fonte única'
);
SELECT ok(
  :'changed_normalized_diff'::jsonb @> '{"entries":[{"path":"/system"}]}'::jsonb,
  'RPC devolve normalized_diff persistido sem duplicar em detected_change'
);
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.process_comparison WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 2, 'há uma comparação por snapshot corrente e versão');
SELECT is((SELECT count(*)::integer FROM public.detected_change WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 1, 'changed cria exatamente uma mudança');
SELECT ok((SELECT normalized_diff @> '{"entries":[{"path":"/system"}]}'::jsonb
             FROM public.process_comparison
            WHERE id = :'changed_comparison_id'), 'process_comparison mantém o diff completo');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'detected_change'
     AND column_name IN ('changed_fields', 'normalized_diff')
), 'detected_change não duplica o diff');
SELECT throws_ok(
  $$SELECT * FROM public.phase10_compare_process_snapshot_v2('a1000000-0000-4000-1000-000000000002', 'comparison-v1', 'changed', NULL, '["/wrong"]', '{"entries":[{"path":"/system","changeType":"field_updated","before":"synthetic-system","after":"synthetic-system-v2"}]}' )$$,
  '22023', 'changed_fields must match normalized_diff paths', 'changed_fields divergente do diff é rejeitado'
);
SET ROLE service_role;

SELECT * FROM public.phase10_compare_process_snapshot_v2(
  'a1000000-0000-4000-1000-000000000002', 'comparison-v1', 'changed', NULL,
  '["/system", "/movements/by-ref/M-1/description"]',
  '{"entries":[{"path":"/system","changeType":"field_updated","before":"synthetic-system","after":"synthetic-system-v2"},{"path":"/movements/by-ref/M-1/description","changeType":"movement_updated","before":"Movimento antigo","after":"Movimento novo"}]}'
) \gset replay_
SELECT is(:'replay_replayed'::text, 't'::text, 'mesma dupla e versão é replay idempotente');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.process_comparison WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 2, 'replay não duplica comparação');
SELECT is((SELECT count(*)::integer FROM public.detected_change WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 1, 'replay não duplica detected_change');
SET ROLE service_role;

SELECT * FROM public.phase10_compare_process_snapshot_v2(
  'a1000000-0000-4000-1000-000000000003', 'comparison-v1', 'unchanged', NULL,
  '[]', '{"entries":[]}'
) \gset unchanged_
SELECT is(:'unchanged_result'::text, 'unchanged'::text, 'snapshot igual produz unchanged');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.detected_change WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 1, 'unchanged não cria detected_change');
SET ROLE service_role;

SELECT throws_ok(
  $$SELECT * FROM public.phase10_compare_process_snapshot_v2('a1000000-0000-4000-1000-000000000003', 'custom', 'unchanged', NULL, '[]', '{"entries":[]}')$$,
  '22023', NULL, 'versão de comparação desconhecida é rejeitada'
);

SET ROLE authenticated;
SELECT throws_ok(
  $$SELECT * FROM public.phase10_compare_process_snapshot_v2('a1000000-0000-4000-1000-000000000003', 'comparison-v1', 'unchanged', NULL, '[]', '{"entries":[]}')$$,
  '42501', NULL, 'browser não possui EXECUTE da comparação'
);
RESET ROLE;
SET ROLE anon;
SELECT throws_ok(
  $$SELECT * FROM public.phase10_compare_process_snapshot_v2('a1000000-0000-4000-1000-000000000003', 'comparison-v1', 'unchanged', NULL, '[]', '{"entries":[]}')$$,
  '42501', NULL, 'anon não possui EXECUTE da comparação'
);
RESET ROLE;

CREATE OR REPLACE FUNCTION pg_temp.fail_phase10_audit()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.action LIKE 'comparison.%' OR NEW.action = 'detected_change.created' THEN
    RAISE EXCEPTION 'synthetic phase 10 audit failure';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER phase10_test_fail_audit
BEFORE INSERT ON public.audit_log
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_phase10_audit();
SET ROLE service_role;
SELECT throws_ok(
  $$SELECT * FROM public.phase10_compare_process_snapshot_v2('a1000000-0000-4000-1000-000000000004', 'comparison-v1', 'changed', NULL, '["/system"]', '{"entries":[{"path":"/system","changeType":"field_updated","before":"x","after":"y"}]}')$$,
  NULL, 'synthetic phase 10 audit failure', 'falha de auditoria faz rollback da comparação'
);
RESET ROLE;
DROP TRIGGER phase10_test_fail_audit ON public.audit_log;
SELECT is((SELECT count(*)::integer FROM public.process_comparison WHERE office_id = 'a1000000-0000-4000-9000-000000000001'::uuid), 3, 'rollback não deixa comparação parcial');

SELECT ok(
  NOT has_table_privilege('service_role', 'public.process_comparison', 'UPDATE')
  AND NOT has_table_privilege('service_role', 'public.process_comparison', 'DELETE'),
  'service_role não possui UPDATE/DELETE direto na evidência comparativa'
);

SELECT * FROM finish();
