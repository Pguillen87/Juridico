INSERT INTO auth.users (id, email)
VALUES
  ('c1200000-0000-4000-8000-000000000001', 'phase12-lawyer@example.test'),
  ('c1200000-0000-4000-8000-000000000002', 'phase12-reviewer@example.test'),
  ('c1200000-0000-4000-8000-000000000003', 'phase12-operator@example.test'),
  ('c1200000-0000-4000-8000-000000000004', 'phase12-auditor@example.test'),
  ('c1200000-0000-4000-8000-000000000005', 'phase12-other-office@example.test'),
  ('c1200000-0000-4000-8000-000000000006', 'phase12-owner-reviewer@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('c1200000-0000-4000-9000-000000000001', 'Phase 12 Synthetic Office', true),
  ('c1200000-0000-4000-9000-000000000002', 'Phase 12 Other Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = excluded.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES
  ('c1200000-0000-4000-8000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'Phase 12 Lawyer', 'lawyer', false, true),
  ('c1200000-0000-4000-8000-000000000002', 'c1200000-0000-4000-9000-000000000001', 'Phase 12 Reviewer', 'reviewer', false, true),
  ('c1200000-0000-4000-8000-000000000003', 'c1200000-0000-4000-9000-000000000001', 'Phase 12 Operator', 'operator', false, true),
  ('c1200000-0000-4000-8000-000000000004', 'c1200000-0000-4000-9000-000000000001', 'Phase 12 Auditor', 'auditor', false, true),
  ('c1200000-0000-4000-8000-000000000005', 'c1200000-0000-4000-9000-000000000002', 'Phase 12 Other Reviewer', 'reviewer', false, true),
  ('c1200000-0000-4000-8000-000000000006', 'c1200000-0000-4000-9000-000000000001', 'Phase 12 Owner Reviewer', 'reviewer', true, true)
ON CONFLICT (id) DO UPDATE SET office_id = excluded.office_id, role = excluded.role,
  is_owner = excluded.is_owner, is_active = excluded.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES
  ('c1200000-0000-4000-a000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'person', 'Phase 12 Client Party', 'phase 12 client party', 'c1200000-0000-4000-8000-000000000001'),
  ('c1200000-0000-4000-a000-000000000002', 'c1200000-0000-4000-9000-000000000002', 'person', 'Phase 12 Other Party', 'phase 12 other party', 'c1200000-0000-4000-8000-000000000001'),
  ('c1200000-0000-4000-a000-000000000003', 'c1200000-0000-4000-9000-000000000001', 'person', 'Phase 12 Unproven Party', 'phase 12 unproven party', 'c1200000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES
  ('c1200000-0000-4000-b000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-a000-000000000001', 'c1200000-0000-4000-8000-000000000001'),
  ('c1200000-0000-4000-b000-000000000002', 'c1200000-0000-4000-9000-000000000002', 'c1200000-0000-4000-a000-000000000002', 'c1200000-0000-4000-8000-000000000001'),
  ('c1200000-0000-4000-b000-000000000003', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-a000-000000000003', 'c1200000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by, created_at
) VALUES
  ('c1200000-0000-4000-c000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-b000-000000000001', '12000000000000000011', 'TJ-SYNTHETIC', 'Phase12', true, 'active', 'active', 'c1200000-0000-4000-8000-000000000001', '2026-08-20 10:00:00+00'),
  ('c1200000-0000-4000-c000-000000000002', 'c1200000-0000-4000-9000-000000000002', 'c1200000-0000-4000-b000-000000000002', '12000000000000000012', 'TJ-SYNTHETIC', 'Phase12', true, 'active', 'active', 'c1200000-0000-4000-8000-000000000001', '2026-08-20 10:00:00+00'),
  ('c1200000-0000-4000-c000-000000000003', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-b000-000000000003', '12000000000000000013', 'TJ-SYNTHETIC', 'Phase12', true, 'active', 'active', 'c1200000-0000-4000-8000-000000000001', '2026-08-20 10:00:00+00')
ON CONFLICT (id) DO UPDATE SET client_id = excluded.client_id;

INSERT INTO public.audit_log (
  audit_scope, office_id, actor_user_id, action, entity_type, entity_id, metadata, created_at
) VALUES
  ('operational', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-8000-000000000001', 'process.created', 'legal_process', 'c1200000-0000-4000-c000-000000000001', jsonb_build_object('after', jsonb_build_object('client_id', 'c1200000-0000-4000-b000-000000000001')), '2026-08-20 10:00:01+00'),
  ('operational', 'c1200000-0000-4000-9000-000000000002', 'c1200000-0000-4000-8000-000000000001', 'process.created', 'legal_process', 'c1200000-0000-4000-c000-000000000002', jsonb_build_object('after', jsonb_build_object('client_id', 'c1200000-0000-4000-b000-000000000002')), '2026-08-20 10:00:01+00')
ON CONFLICT DO NOTHING;

INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at, finished_at, created_at
) VALUES
  ('c1200000-0000-4000-d000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation', 'scheduled', '2026-08-22 10:00:00+00', 'phase12-job-1', repeat('1', 64), 'phase12-job-1', 'succeeded', 1, 3, '2026-08-22 10:00:00+00', '2026-08-22 10:00:01+00', '2026-08-22 10:00:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.provider_exchange (
  id, office_id, process_id, provider_id, source, contract_version,
  subject_ref, correlation_id, request_fingerprint, result_kind, result_status,
  normalized_result, created_at
) VALUES (
  'c1200000-0000-4000-e000-000000000002',
  'c1200000-0000-4000-9000-000000000001',
  'c1200000-0000-4000-c000-000000000001',
  'datajud_sandbox', 'datajud', 1, '12000000000000000011',
  'phase12-exchange-1', repeat('2', 64), 'observation', 'observed',
  '{"data":{"processRef":"12000000000000000011","tribunal":"TJ-SYNTHETIC","system":"Phase12","movements":[],"parties":[]},"evidence":{"evidenceRef":"synthetic-evidence-12"}}',
  '2026-08-22 10:00:01+00'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_execution (
  id, office_id, query_job_id, process_id, provider_id, capability,
  attempt_number, status, started_at, finished_at, duration_ms,
  provider_exchange_id, correlation_id, created_at
) VALUES
  ('c1200000-0000-4000-e000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-d000-000000000001', 'c1200000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation', 1, 'succeeded', '2026-08-22 10:00:00+00', '2026-08-22 10:00:01+00', 100, 'c1200000-0000-4000-e000-000000000002', 'phase12-exec-1', '2026-08-22 10:00:00+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.process_snapshot (
  id, office_id, process_id, query_execution_id, provider_id, source,
  normalizer_version, normalized_data, missing_fields, snapshot_hash, created_at
) VALUES
  ('c1200000-0000-4000-f000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-c000-000000000001', 'c1200000-0000-4000-e000-000000000001', 'datajud_sandbox', 'datajud', 'normalizer-v1', '{"processRef":"synthetic-12","tribunal":"TJ-SYNTHETIC","system":"Phase12","movements":[],"parties":[]}', '[]', repeat('a', 64), '2026-08-22 10:00:02+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.process_comparison (
  id, office_id, process_id, previous_snapshot_id, current_snapshot_id,
  comparison_version, result, changed_fields, normalized_diff, comparison_hash, created_at
) VALUES (
  'c1200000-0000-4000-0000-000000000001', 'c1200000-0000-4000-9000-000000000001', 'c1200000-0000-4000-c000-000000000001', NULL, 'c1200000-0000-4000-f000-000000000001', 'comparison-v1', 'changed', '["/movements/by-ref/m-1"]', '{"entries":[{"path":"/movements/by-ref/m-1","changeType":"movement_added","after":{"movementRef":"m-1"}}]}', repeat('b', 64), '2026-08-22 10:00:03+00'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.detected_change (
  id, office_id, process_id, comparison_id, change_fingerprint, change_type,
  detected_at, created_at
) VALUES (
  'c1200000-0000-4000-0000-000000000002',
  'c1200000-0000-4000-9000-000000000001',
  'c1200000-0000-4000-c000-000000000001',
  'c1200000-0000-4000-0000-000000000001', repeat('f', 64), 'snapshot_changed',
  '2026-08-22 10:00:04+00', '2026-08-22 10:00:04+00'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.failure_incident (
  id, office_id, process_id, origin, provider_id, capability, failure_stage,
  failure_class, failure_code, fingerprint, recovery_key, occurrence_count,
  current_execution_id, current_job_id, created_at, updated_at
) VALUES (
  'c1200000-0000-4000-f100-000000000001',
  'c1200000-0000-4000-9000-000000000001',
  'c1200000-0000-4000-c000-000000000001',
  'query_execution', 'datajud_sandbox', 'process_observation', 'provider',
  'provider_transient', 'timeout', repeat('d', 64), repeat('e', 64), 1,
  'c1200000-0000-4000-e000-000000000001',
  'c1200000-0000-4000-d000-000000000001',
  '2026-08-28 20:00:00+00', '2026-08-28 20:00:00+00'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.failure_occurrence (
  id, office_id, incident_id, event_kind, process_id, origin, failure_stage,
  failure_class, failure_code, source_type, source_id, query_execution_id,
  query_job_id, attempt_number, sanitized_message_code,
  occurrence_idempotency_key, occurred_at, created_at
) VALUES (
  'c1200000-0000-4000-f100-000000000002',
  'c1200000-0000-4000-9000-000000000001',
  'c1200000-0000-4000-f100-000000000001', 'failure_observed',
  'c1200000-0000-4000-c000-000000000001', 'query_execution', 'provider',
  'provider_transient', 'timeout', 'query_execution', 'phase12-exec-1',
  'c1200000-0000-4000-e000-000000000001',
  'c1200000-0000-4000-d000-000000000001', 1, 'timeout',
  'phase12-cutoff-failure', '2026-08-28 20:00:00+00', '2026-08-28 20:00:00+00'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.process_party (
  id, office_id, process_id, party_id, role_in_process, source,
  confirmation_status, status, created_by, created_at
) VALUES (
  'c1200000-0000-4000-c000-000000000011',
  'c1200000-0000-4000-9000-000000000001',
  'c1200000-0000-4000-c000-000000000001',
  'c1200000-0000-4000-a000-000000000003',
  'interested_party', 'manual', 'pending', 'active',
  'c1200000-0000-4000-8000-000000000001', '2026-08-20 10:00:04+00'
) ON CONFLICT (id) DO NOTHING;

SELECT plan(58);

SELECT is((SELECT count(*)::integer FROM pg_class WHERE relname IN ('weekly_report', 'report_version', 'report_process', 'report_party', 'report_command_idempotency') AND relrowsecurity), 5, 'tabelas da Fase 12 têm RLS habilitada');
SELECT ok(NOT has_table_privilege('authenticated', 'public.weekly_report', 'INSERT'), 'authenticated não insere relatório diretamente');
SELECT ok(NOT has_table_privilege('authenticated', 'public.report_version', 'UPDATE'), 'authenticated não atualiza versão diretamente');
SELECT ok(NOT has_table_privilege('authenticated', 'public.report_process', 'INSERT'), 'authenticated não insere projeção diretamente');
SELECT ok(NOT has_table_privilege('authenticated', 'public.report_command_idempotency', 'SELECT'), 'idempotência não é leitura genérica do browser');
SELECT ok(NOT has_function_privilege('authenticated', 'public.phase12_generate_weekly_report(uuid,uuid,timestamptz,timestamptz,timestamptz)'::regprocedure, 'EXECUTE'), 'geração é backend-only');
SELECT ok(has_function_privilege('service_role', 'public.phase12_generate_weekly_report(uuid,uuid,timestamptz,timestamptz,timestamptz)'::regprocedure, 'EXECUTE'), 'service_role executa geração backend-only');
SELECT ok(NOT has_function_privilege('service_role', 'public.phase12_approve_report(uuid,uuid,text)'::regprocedure, 'EXECUTE'), 'service_role não é ator jurídico de aprovação');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000001', false);
SELECT throws_ok($$UPDATE public.weekly_report SET status = 'approved'$$, '42501', NULL, 'browser não atualiza relatório diretamente');
RESET ROLE;

SET ROLE service_role;
SELECT throws_ok(
  $$SELECT public.phase12_generate_weekly_report(
    'c1200000-0000-4000-9000-000000000001',
    'c1200000-0000-4000-b000-000000000003',
    '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00')$$,
  'P0001', 'manual_review_required', 'vínculo cliente-processo sem prova histórica falha fechado'
);
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.weekly_report WHERE client_id = 'c1200000-0000-4000-b000-000000000003'), 0, 'falha histórica não cria relatório parcial');
SET ROLE service_role;

SELECT report_id, version_id, replayed
  FROM public.phase12_generate_weekly_report(
    'c1200000-0000-4000-9000-000000000001',
    'c1200000-0000-4000-b000-000000000001',
    '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00')
  \gset generated_
RESET ROLE;
SELECT ok(:'generated_report_id' IS NOT NULL, 'geração cria weekly_report sintético');
SELECT ok(:'generated_version_id' IS NOT NULL, 'geração cria a primeira versão');
SELECT is((SELECT content_hash FROM public.report_version WHERE id = :'generated_version_id'), public.phase12_hash_version('report-v1', '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', (SELECT structured_content FROM public.report_version WHERE id = :'generated_version_id'), (SELECT source_manifest FROM public.report_version WHERE id = :'generated_version_id')), 'hash da versão é verificável');
SELECT is((SELECT jsonb_array_length(structured_content->'processes'->0->'changed') FROM public.report_version WHERE id = :'generated_version_id'), 1, 'alteração vem da comparação persistida');
SELECT ok((SELECT structured_content->'processes'->0->'changed'->0->>'detected_change_id' IS NOT NULL FROM public.report_version WHERE id = :'generated_version_id'), 'alteração mantém referência à detecção persistida');
SELECT is((SELECT jsonb_array_length(structured_content->'processes'->0->'unchanged') FROM public.report_version WHERE id = :'generated_version_id'), 0, 'ausência de alteração não é inventada');
SELECT is((SELECT jsonb_array_length(structured_content->'processes'->0->'not_comparable') FROM public.report_version WHERE id = :'generated_version_id'), 0, 'não comparável permanece separado');
SELECT is((SELECT jsonb_array_length(structured_content->'processes'->0->'failures') FROM public.report_version WHERE id = :'generated_version_id'), 0, 'falha ausente não é inventada');
SELECT is((SELECT (structured_content->'processes'->0->>'manual_review_required')::boolean FROM public.report_version WHERE id = :'generated_version_id'), true, 'relação processo-parte sem prova permanece pendente');
SELECT is((SELECT occurrence_count FROM public.failure_incident WHERE id = 'c1200000-0000-4000-f100-000000000001'), 1, 'occurrence_count representa observações, não número da tentativa');
SELECT is((SELECT structured_content->'parties'->0->>'relationship_state' FROM public.report_version WHERE id = :'generated_version_id'), 'pending', 'parte ambígua não é confirmada automaticamente');
SELECT is((SELECT count(*)::integer FROM public.report_version WHERE report_id = :'generated_report_id'::uuid), 1, 'primeira geração cria uma única versão');
SET ROLE service_role;
SELECT report_id, version_id, replayed
  FROM public.phase12_generate_weekly_report(
    'c1200000-0000-4000-9000-000000000001',
    'c1200000-0000-4000-b000-000000000001',
    '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00')
  \gset replay_
RESET ROLE;
SELECT is(:'replay_replayed'::boolean, true, 'geração repetida é idempotente');
SELECT is((SELECT count(*)::integer FROM public.report_version WHERE report_id = :'generated_report_id'::uuid), 1, 'replay não cria segunda versão');
SET ROLE service_role;
SELECT report_id, version_id, replayed
  FROM public.phase12_generate_weekly_report(
    'c1200000-0000-4000-9000-000000000002',
    'c1200000-0000-4000-b000-000000000002',
    '2026-08-21 20:00:00+00', '2026-08-28 20:00:00+00', '2026-08-28 21:00:00+00')
  \gset other_
SELECT ok(:'other_report_id' IS NOT NULL, 'outro escritório consegue gerar sua própria série');
RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000001', false);
SELECT is((SELECT count(*)::integer FROM public.weekly_report), 1, 'lawyer vê somente relatórios do próprio escritório');
SELECT is((SELECT count(*)::integer FROM public.report_version), 1, 'lawyer vê somente versões do próprio escritório');
SELECT ok(has_function_privilege('authenticated', 'public.phase12_approve_report(uuid,uuid,text)'::regprocedure, 'EXECUTE'), 'approve report é fronteira RPC autenticada');
SELECT ok(NOT has_function_privilege('authenticated', 'public.phase12_write_audit_internal(text,text,uuid,uuid,uuid,jsonb)'::regprocedure, 'EXECUTE'), 'helper de auditoria não é exposto');

SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000003', false);
SELECT is((SELECT count(*)::integer FROM public.weekly_report), 0, 'operator não recebe visibilidade de relatório');
SELECT throws_ok($$SELECT public.phase12_approve_report(:'generated_report_id'::uuid, :'generated_version_id'::uuid, 'operator-approve')$$, '42501', 'permission denied', 'operator não aprova');
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000004', false);
SELECT is((SELECT count(*)::integer FROM public.weekly_report), 0, 'auditor não recebe visibilidade de relatório');
SELECT throws_ok($$SELECT public.phase12_cancel_report(:'generated_report_id'::uuid, 'other', 'auditor-cancel')$$, '42501', 'permission denied', 'auditor não cancela');
RESET ROLE;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000002', false);
SELECT lives_ok(
  format(
    'SELECT public.phase12_create_editorial_version(%L::uuid, %L::uuid, %L::jsonb, %L)',
    :'generated_report_id', :'generated_version_id', '{"summary_note":"Nota sintética"}', 'phase12-edit-1'
  ),
  'reviewer cria versão editorial'
);
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.report_version WHERE report_id = :'generated_report_id'::uuid), 2, 'versão editorial é append-only');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000002', false);
SELECT phase12_submit_report(:'generated_report_id'::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = :'generated_report_id'::uuid), 'phase12-submit-1');
SELECT phase12_return_report_to_draft(:'generated_report_id'::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = :'generated_report_id'::uuid), 'phase12-return-1');
SELECT lives_ok(
  format(
    'SELECT public.phase12_restore_report_version(%L::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = %L::uuid), %L::uuid, %L)',
    :'generated_report_id', :'generated_report_id', :'generated_version_id', 'phase12-restore-1'
  ),
  'restauração cria nova versão sem sobrescrever histórico'
);
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.report_version WHERE report_id = :'generated_report_id'::uuid), 3, 'restauração cria V3 e preserva V1/V2');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000002', false);
SELECT throws_ok(
  format(
    'SELECT public.phase12_approve_report(%L::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = %L::uuid), %L)',
    :'generated_report_id', :'generated_report_id', 'reviewer-approve'
  ),
  '42501', 'permission denied', 'reviewer não aprova'
);
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000006', false);
SELECT throws_ok(
  format(
    'SELECT public.phase12_approve_report(%L::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = %L::uuid), %L)',
    :'generated_report_id', :'generated_report_id', 'owner-reviewer-approve'
  ),
  '42501', 'permission denied', 'is_owner não concede poder de aprovação'
);
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000002', false);
SELECT throws_ok(
  format(
    'SELECT public.phase12_create_editorial_version(%L::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = %L::uuid), %L::jsonb, %L)',
    :'generated_report_id', :'generated_report_id', '{"not_allowed":"não"}', 'invalid-editorial'
  ),
  '22023', 'invalid editorial content', 'campo editorial não allowlisted é rejeitado no banco'
);
SELECT phase12_submit_report(:'generated_report_id'::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = :'generated_report_id'::uuid), 'phase12-submit-2');
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000001', false);
SELECT lives_ok(
  format(
    'SELECT public.phase12_approve_report(%L::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = %L::uuid), %L)',
    :'generated_report_id', :'generated_report_id', 'phase12-approve-1'
  ),
  'somente lawyer aprova e o hash é recalculado'
);
RESET ROLE;
SELECT is((SELECT status FROM public.weekly_report WHERE id = :'generated_report_id'::uuid), 'approved', 'aprovação muda o estado');
SELECT is((SELECT approved_hash FROM public.weekly_report WHERE id = :'generated_report_id'::uuid), (SELECT content_hash FROM public.report_version WHERE id = (SELECT approved_version_id FROM public.weekly_report WHERE id = :'generated_report_id'::uuid)), 'approved_hash aponta para a versão aprovada');

ALTER TABLE public.report_version DISABLE TRIGGER tr_report_version_append_only;
UPDATE public.report_version SET content_hash = repeat('c', 64) WHERE id = (SELECT approved_version_id FROM public.weekly_report WHERE id = :'generated_report_id'::uuid);
ALTER TABLE public.report_version ENABLE TRIGGER tr_report_version_append_only;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000001', false);
SELECT throws_ok(
  format(
    'SELECT public.phase12_approve_report(%L::uuid, (SELECT approved_version_id FROM public.weekly_report WHERE id = %L::uuid), %L)',
    :'generated_report_id', :'generated_report_id', 'phase12-approve-corrupt'
  ),
  '23514', 'report version hash mismatch', 'aprovação falha fechado com hash corrompido'
);
RESET ROLE;
ALTER TABLE public.report_version DISABLE TRIGGER tr_report_version_append_only;
UPDATE public.report_version rv
   SET content_hash = public.phase12_hash_version(
     rv.schema_version, wr.period_start_utc, wr.period_end_utc,
     rv.structured_content, rv.source_manifest
   )
  FROM public.weekly_report wr
 WHERE rv.id = wr.approved_version_id
   AND wr.id = :'generated_report_id'::uuid;
ALTER TABLE public.report_version ENABLE TRIGGER tr_report_version_append_only;
SELECT is((SELECT status FROM public.weekly_report WHERE id = :'generated_report_id'::uuid), 'approved', 'falha de hash não altera o estado aprovado');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000001', false);
SELECT lives_ok(
  format('SELECT public.phase12_cancel_report(%L::uuid, %L, %L)', :'generated_report_id', 'incorrect_content', 'phase12-cancel-1'),
  'lawyer cancela relatório'
);
SELECT lives_ok(
  format('SELECT public.phase12_cancel_report(%L::uuid, %L, %L)', :'generated_report_id', 'incorrect_content', 'phase12-cancel-1'),
  'cancelamento repetido é idempotente'
);
SELECT throws_ok(
  format('SELECT public.phase12_cancel_report(%L::uuid, %L, %L)', :'generated_report_id', 'other', 'phase12-cancel-2'),
  'P0001', 'report cannot be cancelled', 'cancelamento novo é bloqueado após terminalidade'
);
SELECT throws_ok(
  format(
    'SELECT public.phase12_create_editorial_version(%L::uuid, (SELECT current_version_id FROM public.weekly_report WHERE id = %L::uuid), %L::jsonb, %L)',
    :'generated_report_id', :'generated_report_id', '{"summary_note":"não"}', 'phase12-edit-cancelled'
  ),
  'P0001', 'report is not editable', 'cancelled é terminal e não aceita nova versão'
);
RESET ROLE;
SELECT is((SELECT status FROM public.weekly_report WHERE id = :'generated_report_id'::uuid), 'cancelled', 'cancelamento preserva estado terminal');
SELECT is((SELECT count(*)::integer FROM public.report_version WHERE report_id = :'generated_report_id'::uuid), 3, 'cancelamento não cria versão');
SELECT ok((SELECT wr.approved_version_id IS NOT NULL
  AND wr.approved_hash IS NOT NULL
  AND wr.approved_hash = rv.content_hash
  FROM public.weekly_report wr
  JOIN public.report_version rv ON rv.id = wr.approved_version_id
 WHERE wr.id = :'generated_report_id'::uuid), 'cancelamento preserva ponteiro e hash da aprovação');
SELECT is((SELECT count(*)::integer FROM public.audit_log WHERE entity_id = :'generated_report_id'::uuid AND action = 'weekly_report.approved'), 1, 'aprovação grava auditoria operacional');
SELECT is((SELECT count(*)::integer FROM public.audit_log WHERE entity_id = :'generated_report_id'::uuid AND action = 'weekly_report.cancelled'), 1, 'cancelamento grava auditoria operacional');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000001', false);
SELECT is((SELECT count(*)::integer FROM public.weekly_report WHERE office_id = 'c1200000-0000-4000-9000-000000000002'), 0, 'relatório de outro escritório nunca aparece');
RESET ROLE;

UPDATE public.user_profile SET is_active = false WHERE id = 'c1200000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'c1200000-0000-4000-8000-000000000001', false);
SELECT is((SELECT count(*)::integer FROM public.weekly_report), 0, 'perfil inativo não vê relatórios');
RESET ROLE;
UPDATE public.user_profile SET is_active = true WHERE id = 'c1200000-0000-4000-8000-000000000001';
UPDATE public.office SET is_active = false WHERE id = 'c1200000-0000-4000-9000-000000000001';
SET ROLE authenticated;
SELECT is((SELECT count(*)::integer FROM public.weekly_report), 0, 'escritório inativo não vê relatórios');
RESET ROLE;
UPDATE public.office SET is_active = true WHERE id = 'c1200000-0000-4000-9000-000000000001';

SELECT * FROM finish();
