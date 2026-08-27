INSERT INTO auth.users (id, email)
VALUES ('a2000000-0000-4000-8000-000000000001', 'phase10-compatible@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('a2000000-0000-4000-9000-000000000001', 'Phase 10 Compatible Office', true),
  ('a2000000-0000-4000-9000-000000000002', 'Phase 10 Other Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = excluded.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES (
  'a2000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'Phase 10 Compatible Lawyer', 'lawyer', false, true
)
ON CONFLICT (id) DO UPDATE SET office_id = excluded.office_id, role = excluded.role,
  is_owner = excluded.is_owner, is_active = excluded.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES (
  'a2000000-0000-4000-a000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'person', 'Phase 10 Compatible Party', 'phase 10 compatible party',
  'a2000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES (
  'a2000000-0000-4000-b000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-a000-000000000001', 'active',
  'a2000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES (
  'a2000000-0000-4000-a000-000000000002',
  'a2000000-0000-4000-9000-000000000002',
  'person', 'Phase 10 Other Office Party', 'phase 10 other office party',
  'a2000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES (
  'a2000000-0000-4000-b000-000000000002',
  'a2000000-0000-4000-9000-000000000002',
  'a2000000-0000-4000-a000-000000000002', 'active',
  'a2000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
) VALUES (
  'a2000000-0000-4000-c000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-b000-000000000001',
  '20000000000000000002', 'TJ-SYNTHETIC', 'compatible-system', true,
  'active', 'active', 'a2000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO UPDATE SET is_public = excluded.is_public,
  monitoring_status = excluded.monitoring_status, status = excluded.status;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system, is_public,
  monitoring_status, status, created_by
) VALUES (
  'a2000000-0000-4000-c000-000000000002',
  'a2000000-0000-4000-9000-000000000002',
  'a2000000-0000-4000-b000-000000000002',
  '20000000000000000003', 'TJ-SYNTHETIC', 'other-office-system', true,
  'active', 'active', 'a2000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_job (
  id, office_id, process_id, provider_id, capability, job_kind,
  scheduled_window_utc, idempotency_key, request_fingerprint, correlation_id,
  status, attempt_count, max_attempts, available_at, finished_at
) VALUES
(
  'a2000000-0000-4000-d000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-27 12:00:00+00',
  'phase10-compatible-job-a', repeat('a', 64), 'f10-compatible-a',
  'succeeded', 1, 3, '2026-08-27 12:00:00+00', '2026-08-27 12:00:01+00'
),
(
  'a2000000-0000-4000-d000-000000000002',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-27 12:01:00+00',
  'phase10-compatible-job-b', repeat('b', 64), 'f10-compatible-b',
  'succeeded', 1, 3, '2026-08-27 12:01:00+00', '2026-08-27 12:01:01+00'
),
(
  'a2000000-0000-4000-d000-000000000003',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-27 12:02:00+00',
  'phase10-compatible-job-d', repeat('d', 64), 'f10-compatible-d',
  'succeeded', 1, 3, '2026-08-27 12:02:00+00', '2026-08-27 12:02:01+00'
),
(
  'a2000000-0000-4000-d000-000000000004',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-27 12:03:00+00',
  'phase10-compatible-job-e', repeat('e', 64), 'f10-compatible-e',
  'succeeded', 1, 3, '2026-08-27 12:03:00+00', '2026-08-27 12:03:01+00'
),
(
  'a2000000-0000-4000-d000-000000000005',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-27 12:04:00+00',
  'phase10-compatible-job-c', repeat('c', 64), 'f10-compatible-c',
  'succeeded', 1, 3, '2026-08-27 12:04:00+00', '2026-08-27 12:04:01+00'
),
(
  'a2000000-0000-4000-d000-000000000006',
  'a2000000-0000-4000-9000-000000000002',
  'a2000000-0000-4000-c000-000000000002', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-27 11:59:00+00',
  'phase10-compatible-job-cross-office', repeat('f', 64), 'f10-compatible-cross',
  'succeeded', 1, 3, '2026-08-27 11:59:00+00', '2026-08-27 11:59:01+00'
),
(
  'a2000000-0000-4000-d000-000000000007',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox',
  'process_observation', 'scheduled', '2026-08-27 12:05:00+00',
  'phase10-compatible-job-no-baseline', repeat('7', 64), 'f10-compatible-g',
  'succeeded', 1, 3, '2026-08-27 12:05:00+00', '2026-08-27 12:05:01+00'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.provider_exchange (
  id, office_id, process_id, provider_id, source, contract_version,
  subject_ref, correlation_id, request_fingerprint, result_kind, result_status,
  normalized_result
) VALUES
(
  'a2000000-0000-4000-e000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '20000000000000000002', 'f10-compatible-a', repeat('a', 64),
  'observation', 'observed', '{}'
),
(
  'a2000000-0000-4000-e000-000000000002',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '20000000000000000002', 'f10-compatible-b', repeat('b', 64),
  'observation', 'observed', '{}'
),
(
  'a2000000-0000-4000-e000-000000000003',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'manual_observation', 'manual', 1,
  '20000000000000000002', 'f10-compatible-d', repeat('d', 64),
  'observation', 'observed', '{}'
),
(
  'a2000000-0000-4000-e000-000000000004',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '20000000000000000002', 'f10-compatible-e', repeat('e', 64),
  'observation', 'observed', '{}'
),
(
  'a2000000-0000-4000-e000-000000000005',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '20000000000000000002', 'f10-compatible-c', repeat('c', 64),
  'observation', 'observed', '{}'
),
(
  'a2000000-0000-4000-e000-000000000006',
  'a2000000-0000-4000-9000-000000000002',
  'a2000000-0000-4000-c000-000000000002', 'datajud_sandbox', 'datajud', 1,
  '20000000000000000003', 'f10-compatible-cross', repeat('f', 64),
  'observation', 'observed', '{}'
),
(
  'a2000000-0000-4000-e000-000000000007',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'datajud', 1,
  '20000000000000000002', 'f10-compatible-g', repeat('7', 64),
  'observation', 'observed', '{}'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.query_execution (
  id, office_id, query_job_id, process_id, provider_id, capability,
  attempt_number, status, started_at, finished_at, duration_ms,
  provider_exchange_id, correlation_id
) VALUES
(
  'a2000000-0000-4000-f000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-d000-000000000001',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-27 12:00:00+00', '2026-08-27 12:00:01+00', 10,
  'a2000000-0000-4000-e000-000000000001', 'f10-compatible-a'
),
(
  'a2000000-0000-4000-f000-000000000002',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-d000-000000000002',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-27 12:01:00+00', '2026-08-27 12:01:01+00', 10,
  'a2000000-0000-4000-e000-000000000002', 'f10-compatible-b'
),
(
  'a2000000-0000-4000-f000-000000000003',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-d000-000000000003',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-27 12:02:00+00', '2026-08-27 12:02:01+00', 10,
  'a2000000-0000-4000-e000-000000000003', 'f10-compatible-d'
),
(
  'a2000000-0000-4000-f000-000000000004',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-d000-000000000004',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-27 12:03:00+00', '2026-08-27 12:03:01+00', 10,
  'a2000000-0000-4000-e000-000000000004', 'f10-compatible-e'
),
(
  'a2000000-0000-4000-f000-000000000005',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-d000-000000000005',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-27 12:04:00+00', '2026-08-27 12:04:01+00', 10,
  'a2000000-0000-4000-e000-000000000005', 'f10-compatible-c'
),
(
  'a2000000-0000-4000-f000-000000000006',
  'a2000000-0000-4000-9000-000000000002',
  'a2000000-0000-4000-d000-000000000006',
  'a2000000-0000-4000-c000-000000000002', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-27 11:59:00+00', '2026-08-27 11:59:01+00', 10,
  'a2000000-0000-4000-e000-000000000006', 'f10-compatible-cross'
),
(
  'a2000000-0000-4000-f000-000000000007',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-d000-000000000007',
  'a2000000-0000-4000-c000-000000000001', 'datajud_sandbox', 'process_observation',
  1, 'succeeded', '2026-08-27 12:05:00+00', '2026-08-27 12:05:01+00', 10,
  'a2000000-0000-4000-e000-000000000007', 'f10-compatible-g'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.process_snapshot (
  id, office_id, process_id, query_execution_id, provider_id, source,
  normalizer_version, normalized_data, missing_fields, snapshot_hash, created_at
) VALUES
(
  'a2000000-0000-4000-1000-000000000001',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001',
  'a2000000-0000-4000-f000-000000000001', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"compatible-system","movements":[],"parties":[]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"compatible-system","movements":[],"parties":[]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-27 12:00:00+00'
),
(
  'a2000000-0000-4000-1000-000000000002',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001',
  'a2000000-0000-4000-f000-000000000002', 'datajud_sandbox', 'datajud', '2.0.0',
  '{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"different-system","movements":[],"parties":[]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"different-system","movements":[],"parties":[]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-27 12:01:00+00'
),
(
  'a2000000-0000-4000-1000-000000000004',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001',
  'a2000000-0000-4000-f000-000000000003', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"wrong-exchange","movements":[],"parties":[]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"wrong-exchange","movements":[],"parties":[]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-27 12:02:00+00'
),
(
  'a2000000-0000-4000-1000-000000000005',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001',
  'a2000000-0000-4000-f000-000000000004', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"invalid-hash","movements":[],"parties":[]}',
  '[]', repeat('0', 64),
  '2026-08-27 12:03:00+00'
),
(
  'a2000000-0000-4000-1000-000000000003',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001',
  'a2000000-0000-4000-f000-000000000005', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"compatible-system","movements":[],"parties":[]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"compatible-system","movements":[],"parties":[]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-27 12:04:00+00'
),
(
  'a2000000-0000-4000-1000-000000000006',
  'a2000000-0000-4000-9000-000000000002',
  'a2000000-0000-4000-c000-000000000002',
  'a2000000-0000-4000-f000-000000000006', 'datajud_sandbox', 'datajud', '1.0.0',
  '{"processRef":"20000000000000000003","tribunal":"TJ-SYNTHETIC","system":"other-office-system","movements":[],"parties":[]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"20000000000000000003","tribunal":"TJ-SYNTHETIC","system":"other-office-system","movements":[],"parties":[]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-27 11:59:00+00'
),
(
  'a2000000-0000-4000-1000-000000000007',
  'a2000000-0000-4000-9000-000000000001',
  'a2000000-0000-4000-c000-000000000001',
  'a2000000-0000-4000-f000-000000000007', 'datajud_sandbox', 'datajud', '9.0.0',
  '{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"compatible-system","movements":[],"parties":[]}',
  '[]', encode(extensions.digest(convert_to(('{"processRef":"20000000000000000002","tribunal":"TJ-SYNTHETIC","system":"compatible-system","movements":[],"parties":[]}')::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
  '2026-08-27 12:05:00+00'
)
ON CONFLICT (id) DO NOTHING;

SELECT plan(10);

SET ROLE service_role;
SELECT ok(
  public.phase10_resolve_compatible_previous_snapshot(
    'a2000000-0000-4000-1000-000000000003'
  ) = 'a2000000-0000-4000-1000-000000000001'::uuid,
  'C escolhe A como o snapshot compatível mais recente'
);


SELECT * FROM public.phase10_get_snapshot_pair_compatible_internal(
  'a2000000-0000-4000-1000-000000000003'
) WHERE snapshot_role = 'previous' \gset pair_
SELECT * FROM public.phase10_compare_process_snapshot_v2(
  'a2000000-0000-4000-1000-000000000003', 'comparison-v1', 'unchanged', NULL,
  '[]', '{"entries":[]}'
) \gset comparison_
RESET ROLE;

SELECT is(:'pair_id'::text, 'a2000000-0000-4000-1000-000000000001',
  'leitor compatível retorna A como previous de C');
SELECT is(:'comparison_result'::text, 'unchanged',
  'C comparado com A permanece unchanged');
SELECT is((
  SELECT previous_snapshot_id::text
    FROM public.process_comparison
   WHERE current_snapshot_id = 'a2000000-0000-4000-1000-000000000003'::uuid
), 'a2000000-0000-4000-1000-000000000001',
  'persistência registra A como baseline de C');
SELECT is((
  SELECT result
    FROM public.process_comparison
   WHERE current_snapshot_id = 'a2000000-0000-4000-1000-000000000003'::uuid
), 'unchanged',
  'com base A compatível, C produz unchanged sem diff');
SELECT is((
  SELECT count(*)::integer
    FROM public.process_comparison
   WHERE current_snapshot_id = 'a2000000-0000-4000-1000-000000000003'::uuid
), 1,
  'comparação de C é idempotente por snapshot e versão');
SELECT is((
  SELECT count(*)::integer
    FROM public.detected_change
   WHERE comparison_id = (
     SELECT id FROM public.process_comparison
      WHERE current_snapshot_id = 'a2000000-0000-4000-1000-000000000003'::uuid
   )
), 0,
  'unchanged não cria detected_change');
SELECT is((
  SELECT count(*)::integer
    FROM public.phase10_get_snapshot_pair_compatible_internal(
      'a2000000-0000-4000-1000-000000000003'::uuid
    )
), 2,
  'o leitor retorna somente current e previous do mesmo office/processo');
RESET ROLE;

SET ROLE service_role;
SELECT ok(
  public.phase10_resolve_compatible_previous_snapshot(
    'a2000000-0000-4000-1000-000000000007'
  ) IS NULL,
  'sem baseline compatível por normalizer o resolvedor retorna NULL'
);
RESET ROLE;
SELECT ok(
  NOT EXISTS (
    SELECT 1
      FROM public.process_comparison
     WHERE current_snapshot_id = 'a2000000-0000-4000-1000-000000000003'::uuid
       AND previous_snapshot_id IN (
         'a2000000-0000-4000-1000-000000000002'::uuid,
         'a2000000-0000-4000-1000-000000000004'::uuid,
         'a2000000-0000-4000-1000-000000000005'::uuid
       )
  ),
  'B normalizer incompatível, exchange incompatível e hash inválido não são escolhidos'
);

SELECT * FROM finish();
