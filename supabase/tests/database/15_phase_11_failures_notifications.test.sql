INSERT INTO auth.users (id, email)
VALUES
  ('b1100000-0000-4000-8000-000000000001', 'phase11-lawyer@example.test'),
  ('b1100000-0000-4000-8000-000000000002', 'phase11-reviewer@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('b1100000-0000-4000-9000-000000000001', 'Phase 11 Synthetic Office', true),
  ('b1100000-0000-4000-9000-000000000002', 'Phase 11 Other Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = excluded.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES
  ('b1100000-0000-4000-8000-000000000001', 'b1100000-0000-4000-9000-000000000001', 'Phase 11 Lawyer', 'lawyer', false, true),
  ('b1100000-0000-4000-8000-000000000002', 'b1100000-0000-4000-9000-000000000001', 'Phase 11 Reviewer', 'reviewer', false, true)
ON CONFLICT (id) DO UPDATE SET office_id = excluded.office_id, role = excluded.role,
  is_owner = excluded.is_owner, is_active = excluded.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES
  ('b1100000-0000-4000-a000-000000000001', 'b1100000-0000-4000-9000-000000000001', 'person', 'Phase 11 Party', 'phase 11 party', 'b1100000-0000-4000-8000-000000000001'),
  ('b1100000-0000-4000-a000-000000000002', 'b1100000-0000-4000-9000-000000000002', 'person', 'Phase 11 Other Party', 'phase 11 other party', 'b1100000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES
  ('b1100000-0000-4000-b000-000000000001', 'b1100000-0000-4000-9000-000000000001', 'b1100000-0000-4000-a000-000000000001', 'b1100000-0000-4000-8000-000000000001'),
  ('b1100000-0000-4000-b000-000000000002', 'b1100000-0000-4000-9000-000000000002', 'b1100000-0000-4000-a000-000000000002', 'b1100000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
) VALUES
  ('b1100000-0000-4000-c000-000000000001', 'b1100000-0000-4000-9000-000000000001', 'b1100000-0000-4000-b000-000000000001', '11000000000000000011', 'TJ-SYNTHETIC', 'Phase11', true, 'active', 'active', 'b1100000-0000-4000-8000-000000000001'),
  ('b1100000-0000-4000-c000-000000000002', 'b1100000-0000-4000-9000-000000000002', 'b1100000-0000-4000-b000-000000000002', '11000000000000000012', 'TJ-SYNTHETIC', 'Phase11', true, 'active', 'active', 'b1100000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET is_public = excluded.is_public, monitoring_status = excluded.monitoring_status, status = excluded.status;

INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at, finished_at
) VALUES
  ('b1100000-0000-4000-d000-000000000001', 'b1100000-0000-4000-9000-000000000001', 'b1100000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation', 'scheduled', '2026-08-27 10:00:00+00', 'phase11-job-1', repeat('a', 64), 'phase11-job-1', 'terminal_failure', 1, 3, '2026-08-27 10:00:00+00', '2026-08-27 10:00:01+00'),
  ('b1100000-0000-4000-d000-000000000002', 'b1100000-0000-4000-9000-000000000001', 'b1100000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation', 'scheduled', '2026-08-27 10:01:00+00', 'phase11-job-2', repeat('b', 64), 'phase11-job-2', 'retry_scheduled', 2, 3, '2999-01-01 00:00:00+00', NULL),
  ('b1100000-0000-4000-d000-000000000003', 'b1100000-0000-4000-9000-000000000002', 'b1100000-0000-4000-c000-000000000002', 'datajud_sandbox', 'process_observation', 'scheduled', '2026-08-27 10:02:00+00', 'phase11-job-3', repeat('c', 64), 'phase11-job-3', 'terminal_failure', 1, 3, '2026-08-27 10:02:00+00', '2026-08-27 10:02:01+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_execution (
  id, office_id, query_job_id, process_id, provider_id, capability,
  attempt_number, status, started_at, finished_at, duration_ms,
  error_code, error_message_sanitized, correlation_id
) VALUES
  ('b1100000-0000-4000-f000-000000000001', 'b1100000-0000-4000-9000-000000000001', 'b1100000-0000-4000-d000-000000000001', 'b1100000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation', 1, 'terminal_failure', '2026-08-27 10:00:00+00', '2026-08-27 10:00:01+00', 100, 'datajud_timeout', 'A consulta não produziu uma observação válida.', 'phase11-exec-1'),
  ('b1100000-0000-4000-f000-000000000002', 'b1100000-0000-4000-9000-000000000001', 'b1100000-0000-4000-d000-000000000002', 'b1100000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation', 2, 'retry_scheduled', '2026-08-27 10:01:00+00', '2026-08-27 10:01:01+00', 100, 'datajud_timeout', 'A consulta não produziu uma observação válida.', 'phase11-exec-2'),
  ('b1100000-0000-4000-f000-000000000003', 'b1100000-0000-4000-9000-000000000002', 'b1100000-0000-4000-d000-000000000003', 'b1100000-0000-4000-c000-000000000002', 'datajud_sandbox', 'process_observation', 1, 'terminal_failure', '2026-08-27 10:02:00+00', '2026-08-27 10:02:01+00', 100, 'datajud_timeout', 'A consulta não produziu uma observação válida.', 'phase11-exec-3');

SELECT plan(34);

SELECT is((SELECT count(*)::integer FROM pg_class WHERE relname IN ('failure_incident', 'failure_occurrence', 'notification_outbox') AND relrowsecurity), 3, 'tabelas da Fase 11 têm RLS habilitada');
SELECT ok(NOT has_table_privilege('authenticated', 'public.failure_incident', 'INSERT'), 'authenticated não insere incidente diretamente');
SELECT ok(NOT has_table_privilege('authenticated', 'public.failure_incident', 'UPDATE'), 'authenticated não atualiza incidente diretamente');
SELECT ok(NOT has_table_privilege('authenticated', 'public.failure_occurrence', 'DELETE'), 'authenticated não remove ocorrência');
SELECT ok(NOT has_table_privilege('authenticated', 'public.notification_outbox', 'SELECT'), 'outbox não é leitura direta do browser');
SELECT ok(has_function_privilege('authenticated', 'public.phase11_request_failure_reprocess(uuid,text)'::regprocedure, 'EXECUTE'), 'reprocessamento da Fase 11 é exposto somente pelo comando autorizado');
SELECT ok(has_function_privilege('service_role', 'public.phase11_record_execution_failure_internal(uuid)'::regprocedure, 'EXECUTE'), 'reconciliação de execução é backend-only');
SELECT ok(NOT has_function_privilege('authenticated', 'public.phase9_request_manual_reprocess(uuid,text)'::regprocedure, 'EXECUTE'), 'função publicada da Fase 9 continua sem exposição direta');

SET ROLE service_role;
SELECT lives_ok($$SELECT public.phase11_record_failure_event_internal(
  'b1100000-0000-4000-9000-000000000001',
  'b1100000-0000-4000-c000-000000000001', 'provider', 'datajud_sandbox',
  'process_observation', 'provider', 'provider_transient', 'datajud_timeout',
  '{"source":"datajud","capability":"process_observation","failure_stage":"provider"}',
  'b1100000-0000-4000-f000-000000000001', 'b1100000-0000-4000-d000-000000000001',
  NULL, 1, 'query_execution', 'b1100000-0000-4000-f000-000000000001')$$, 'primeira falha cria incidente e ocorrência');
SELECT lives_ok($$SELECT public.phase11_record_failure_event_internal(
  'b1100000-0000-4000-9000-000000000001',
  'b1100000-0000-4000-c000-000000000001', 'provider', 'datajud_sandbox',
  'process_observation', 'provider', 'provider_transient', 'datajud_timeout',
  '{"source":"datajud","capability":"process_observation","failure_stage":"provider"}',
  'b1100000-0000-4000-f000-000000000002', 'b1100000-0000-4000-d000-000000000002',
  NULL, 2, 'query_execution', 'b1100000-0000-4000-f000-000000000002')$$, 'retry posterior preserva o mesmo incidente e nova ocorrência');
SELECT lives_ok($$SELECT public.phase11_record_technical_failure_internal(
  'b1100000-0000-4000-9000-000000000001', 'scheduler', 'scheduler_failure', 'scheduler',
  '{"source":"scheduler","failure_stage":"scheduler"}', 'phase11-scheduler-1')$$, 'falha técnica sem processo cria incidente sem tentativa');
SELECT lives_ok($$SELECT public.phase11_record_failure_event_internal(
  'b1100000-0000-4000-9000-000000000001',
  'b1100000-0000-4000-c000-000000000001', 'provider', 'datajud_sandbox',
  'process_observation', 'provider', 'provider_permanent', 'datajud_not_found',
  '{"source":"datajud","capability":"process_observation","failure_stage":"provider"}',
  NULL, 'b1100000-0000-4000-d000-000000000001', NULL, 1,
  'query_job', 'phase11-manual-test-source')$$, 'falha terminal elegível para o comando de reprocessamento');
SELECT lives_ok($$SELECT public.phase11_record_failure_event_internal(
  'b1100000-0000-4000-9000-000000000002',
  'b1100000-0000-4000-c000-000000000002', 'provider', 'datajud_sandbox',
  'process_observation', 'provider', 'provider_transient', 'datajud_timeout',
  '{"source":"datajud","capability":"process_observation","failure_stage":"provider"}',
  'b1100000-0000-4000-f000-000000000003', 'b1100000-0000-4000-d000-000000000003',
  NULL, 1, 'query_execution', 'b1100000-0000-4000-f000-000000000003')$$, 'outro escritório recebe evidência isolada');
RESET ROLE;

SELECT is((SELECT count(*)::integer FROM public.failure_incident WHERE office_id = 'b1100000-0000-4000-9000-000000000001'), 3, 'office principal tem somente seus incidentes');
SELECT is((SELECT occurrence_count FROM public.failure_incident WHERE office_id = 'b1100000-0000-4000-9000-000000000001' AND failure_code = 'datajud_timeout'), 2, 'occurrence_count conta falhas observadas, não tentativas');
SELECT is((SELECT count(*)::integer FROM public.failure_occurrence WHERE office_id = 'b1100000-0000-4000-9000-000000000001' AND failure_code = 'datajud_timeout' AND attempt_number = 2), 1, 'a segunda tentativa fica registrada na ocorrência');
SELECT is((SELECT count(*)::integer FROM public.failure_occurrence WHERE office_id = 'b1100000-0000-4000-9000-000000000001' AND source_type = 'scheduler' AND attempt_number IS NULL), 1, 'falha sem conceito de tentativa permanece não aplicável');
SELECT is((SELECT count(*)::integer FROM public.notification_outbox WHERE office_id = 'b1100000-0000-4000-9000-000000000001' AND channel = 'mock_email' AND simulation_only), 4, 'outbox cria somente eventos mock_email sintéticos por ocorrência');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000001', false);
SELECT is((SELECT count(*)::integer FROM public.phase11_list_failure_incidents(NULL, NULL, NULL, NULL, NULL, 2, 'open', 50)), 1, 'filtro por tentativa é server-side e retorna a ocorrência correspondente');
SELECT is((SELECT count(*)::integer FROM public.failure_incident WHERE office_id = 'b1100000-0000-4000-9000-000000000002'), 0, 'RLS não expõe incidente de outro office ao lawyer');
SELECT ok(has_function_privilege('authenticated', 'public.phase11_list_failure_incidents(text,uuid,date,date,text,integer,text,integer)'::regprocedure, 'EXECUTE'), 'usuário autorizado consulta a lista por RPC invoker');
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000001', false);
SELECT public.phase11_request_failure_reprocess(
  (SELECT id FROM public.failure_incident WHERE failure_code = 'datajud_not_found' AND office_id = 'b1100000-0000-4000-9000-000000000001'),
  'manual-reprocess-test'
) AS manual_job_id \gset manual_
SELECT ok(:'manual_manual_job_id' IS NOT NULL, 'lawyer solicita reprocessamento pela RPC encapsuladora');
SELECT is((SELECT status FROM public.query_job WHERE id = :'manual_manual_job_id'), 'pending', 'reprocessamento cria job pendente');
SELECT is(public.phase11_request_failure_reprocess(
  (SELECT id FROM public.failure_incident WHERE failure_code = 'datajud_not_found' AND office_id = 'b1100000-0000-4000-9000-000000000001'),
  'manual-reprocess-test'
), :'manual_manual_job_id'::uuid, 'mesma chave de reprocessamento retorna o job existente');
RESET ROLE;
BEGIN;
SELECT set_config('juridico.phase9_internal', '1', true);
UPDATE public.query_job
   SET status = 'cancelled', finished_at = clock_timestamp(), available_at = clock_timestamp(), updated_at = clock_timestamp()
 WHERE id = :'manual_manual_job_id'::uuid;
COMMIT;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000001', false);
SELECT lives_ok($$SELECT public.phase11_assign_failure_incident(
  (SELECT id FROM public.failure_incident WHERE failure_code = 'datajud_not_found' AND office_id = 'b1100000-0000-4000-9000-000000000001'),
  'b1100000-0000-4000-8000-000000000001', 'assignment-test')$$, 'lawyer atribui o incidente no próprio office');
SELECT lives_ok($$SELECT public.phase11_add_failure_note(
  (SELECT id FROM public.failure_incident WHERE failure_code = 'datajud_not_found' AND office_id = 'b1100000-0000-4000-9000-000000000001'),
  'Observação sintética sem dados sensíveis.', 'note-test')$$, 'lawyer adiciona observação sanitizada');
SELECT lives_ok($$SELECT public.phase11_resolve_failure_incident(
  (SELECT id FROM public.failure_incident WHERE failure_code = 'datajud_not_found' AND office_id = 'b1100000-0000-4000-9000-000000000001'),
  'manual_review_complete', 'Revisão concluída no ambiente sintético.', 'resolve-test')$$, 'lawyer resolve incidente com motivo e observação');
RESET ROLE;
SELECT is((SELECT status FROM public.failure_incident WHERE failure_code = 'datajud_not_found' AND office_id = 'b1100000-0000-4000-9000-000000000001'), 'resolved', 'resolução manual atualiza somente o agregado');
SELECT is((SELECT count(*)::integer FROM public.failure_occurrence WHERE failure_code = 'datajud_not_found' AND office_id = 'b1100000-0000-4000-9000-000000000001' AND event_kind IN ('manual_reprocess_requested','assignee_changed','operator_note_added','manual_resolved')), 4, 'tratamento mantém todos os eventos históricos append-only');

SELECT ok(NOT has_function_privilege('authenticated', 'public.phase11_record_failure_event_internal(uuid,uuid,text,text,text,text,text,text,jsonb,uuid,uuid,uuid,integer,text,text)'::regprocedure, 'EXECUTE'), 'browser não executa gravador interno');
SELECT ok(NOT has_table_privilege('service_role', 'public.failure_occurrence', 'UPDATE') AND NOT has_table_privilege('service_role', 'public.notification_outbox', 'DELETE'), 'service_role não recebe mutação direta no histórico/outbox');

CREATE OR REPLACE FUNCTION pg_temp.fail_phase11_audit()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.action LIKE 'failure.%' OR NEW.action LIKE 'notification.%' THEN
    RAISE EXCEPTION 'synthetic phase 11 audit failure';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER phase11_test_fail_audit
BEFORE INSERT ON public.audit_log
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_phase11_audit();
SET ROLE service_role;
SELECT throws_ok(
  $$SELECT public.phase11_record_failure_event_internal(
    'b1100000-0000-4000-9000-000000000001',
    'b1100000-0000-4000-c000-000000000001', 'provider', 'datajud_sandbox',
    'process_observation', 'provider', 'provider_permanent', 'datajud_http_failure',
    '{"source":"datajud","capability":"process_observation","failure_stage":"provider","operation":"atomicity"}',
    NULL, NULL, NULL, NULL, 'provider_exchange', 'atomicity-failure-test')$$,
  NULL, 'synthetic phase 11 audit failure', 'auditoria falha de forma controlada');
RESET ROLE;
DROP TRIGGER phase11_test_fail_audit ON public.audit_log;
SELECT is((SELECT count(*)::integer FROM public.failure_occurrence WHERE source_id = 'atomicity-failure-test'), 0, 'falha de auditoria reverte a ocorrência');
SELECT is((SELECT count(*)::integer FROM public.notification_outbox WHERE payload_sanitized->>'code' = 'datajud_http_failure' AND payload_sanitized->>'event_type' = 'failure_observed' AND office_id = 'b1100000-0000-4000-9000-000000000001'), 0, 'falha de auditoria não deixa outbox parcial');

SELECT * FROM finish();
