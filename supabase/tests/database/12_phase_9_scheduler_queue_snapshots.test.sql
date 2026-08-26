INSERT INTO auth.users (id, email)
VALUES
  ('91000000-0000-4000-8000-000000000001', 'phase9-lawyer@example.test'),
  ('91000000-0000-4000-8000-000000000002', 'phase9-operator@example.test'),
  ('91000000-0000-4000-8000-000000000003', 'phase9-reviewer@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES
  ('91000000-0000-4000-9000-000000000001', 'Phase 9 Active Office', true),
  ('91000000-0000-4000-9000-000000000002', 'Phase 9 Other Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = excluded.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES
  ('91000000-0000-4000-8000-000000000001', '91000000-0000-4000-9000-000000000001', 'Phase 9 Lawyer', 'lawyer', false, true),
  ('91000000-0000-4000-8000-000000000002', '91000000-0000-4000-9000-000000000001', 'Phase 9 Operator', 'operator', false, true),
  ('91000000-0000-4000-8000-000000000003', '91000000-0000-4000-9000-000000000001', 'Phase 9 Reviewer', 'reviewer', false, true)
ON CONFLICT (id) DO UPDATE SET office_id = excluded.office_id, role = excluded.role, is_owner = excluded.is_owner, is_active = excluded.is_active;

INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES
  ('91000000-0000-4000-a000-000000000001', '91000000-0000-4000-9000-000000000001', 'person', 'Phase 9 Party', 'phase 9 party', '91000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES
  ('91000000-0000-4000-b000-000000000001', '91000000-0000-4000-9000-000000000001', '91000000-0000-4000-a000-000000000001', '91000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (id, office_id, client_id, cnj_number, tribunal, system, is_public, monitoring_status, status, created_by)
VALUES
  ('91000000-0000-4000-c000-000000000001', '91000000-0000-4000-9000-000000000001', '91000000-0000-4000-b000-000000000001', '91000000000000000011', 'TJ-SYNTHETIC', 'Sandbox', true, 'paused', 'active', '91000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET is_public = excluded.is_public, monitoring_status = excluded.monitoring_status, status = excluded.status;

SELECT plan(36);

SELECT is((SELECT count(*)::integer
             FROM pg_class
            WHERE relname IN ('monitoring_configuration', 'monitoring_schedule', 'query_job', 'query_execution', 'process_snapshot')
              AND relrowsecurity), 5, 'todas as tabelas novas têm RLS habilitada');
SELECT ok(not has_table_privilege('authenticated', 'public.query_job', 'INSERT'), 'authenticated não insere query_job diretamente');
SELECT ok(not has_table_privilege('authenticated', 'public.query_job', 'UPDATE'), 'authenticated não atualiza query_job diretamente');
SELECT ok(not has_table_privilege('service_role', 'public.query_job', 'INSERT'), 'service_role não recebe INSERT direto em query_job');
SELECT ok(not has_table_privilege('service_role', 'public.query_execution', 'UPDATE'), 'service_role não recebe UPDATE direto em query_execution');
SELECT ok(not has_table_privilege('service_role', 'public.process_snapshot', 'DELETE'), 'service_role não recebe DELETE direto em snapshot');
SELECT ok(not has_function_privilege('authenticated', 'public.phase9_scheduler_tick(timestamptz,integer)'::regprocedure, 'EXECUTE'), 'authenticated não executa scheduler_tick');
SELECT ok(not has_function_privilege('anon', 'public.phase9_claim_query_job(text,integer)'::regprocedure, 'EXECUTE'), 'anon não executa claim');
SELECT ok(has_function_privilege('service_role', 'public.phase9_claim_query_job(text,integer)'::regprocedure, 'EXECUTE'), 'service_role executa claim interno');
SELECT ok(not has_function_privilege('public', 'public.phase9_complete_query_execution(uuid,uuid,uuid,text,text,text,jsonb,jsonb,text,timestamptz,integer,integer,integer)'::regprocedure, 'EXECUTE'), 'PUBLIC não executa completion');
SELECT ok(not has_function_privilege('authenticated', 'public.phase9_request_manual_reprocess(uuid,text)'::regprocedure, 'EXECUTE'), 'authenticated não executa reprocessamento manual sem decisão específica de US-012');
SELECT ok(not has_function_privilege('service_role', 'public.phase9_request_manual_reprocess(uuid,text)'::regprocedure, 'EXECUTE'), 'service_role não executa reprocessamento manual não ativado');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', false);
SELECT lives_ok($$SELECT public.phase9_set_process_monitoring_status('91000000-0000-4000-c000-000000000001', 'active')$$, 'lawyer ativa monitoramento de processo público por RPC de domínio');
SELECT is((SELECT monitoring_status FROM public.legal_process WHERE id = '91000000-0000-4000-c000-000000000001'), 'active', 'processo sandbox fica ativo após autorização D-022');
RESET ROLE;

SET ROLE service_role;
SELECT lives_ok($$SELECT public.phase9_upsert_monitoring_configuration('91000000-0000-4000-9000-000000000001', 'America/Sao_Paulo', true, 1)$$, 'backend cria configuração ativa sintética');
RESET ROLE;
SELECT id AS phase9_configuration_id
  FROM public.monitoring_configuration
 WHERE office_id = '91000000-0000-4000-9000-000000000001'
   AND version = 1
 \gset
SET ROLE service_role;
SELECT lives_ok(
  format($sql$SELECT public.phase9_upsert_monitoring_schedule(%L, '08:00', 'America/Sao_Paulo', ARRAY[4], true)$sql$, :'phase9_configuration_id'),
  'backend cria janela sintética de quinta-feira'
);
SELECT is((SELECT public.phase9_scheduler_tick('2026-01-01T11:00:00Z', 300)), 1, 'scheduler cria um job para a janela devida');
SELECT is((SELECT public.phase9_scheduler_tick('2026-01-01T11:00:00Z', 300)), 0, 'scheduler é idempotente na mesma janela');
SELECT * FROM public.phase9_claim_query_job('phase9-worker-a', 30000) \gset claim_
SELECT ok(:'claim_job_id' IS NOT NULL, 'worker reivindica um job com lease');
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.query_job WHERE status = 'running' AND locked_by = 'phase9-worker-a'), 1, 'segundo worker não rouba job com lease válida');
SET ROLE service_role;
SELECT lives_ok(
  format($sql$
    SELECT * FROM public.phase9_complete_query_execution(
      %L, %L, %L,
      'observation', 'observed', NULL,
      jsonb_build_object(
        'kind', 'observation', 'status', 'observed',
        'provider', jsonb_build_object('providerId', 'datajud_sandbox', 'providerKind', 'datajud', 'adapterVersion', '1.0.0', 'contractVersion', 1),
        'source', 'datajud', 'contractVersion', 1, 'capability', 'process_observation',
        'data', jsonb_build_object('processRef', '91000000000000000011', 'tribunal', 'TJ-SYNTHETIC'),
        'returnedFields', jsonb_build_array('processRef', 'tribunal'),
        'missingFields', jsonb_build_array('system', 'movements', 'parties'),
        'sourceMetadata', jsonb_build_object('sourceType', 'datajud', 'providerId', 'datajud_sandbox', 'adapterVersion', '1.0.0', 'contractVersion', 1, 'observedAt', '2026-01-01T11:00:00Z', 'durationMs', 12),
        'correlationId', %L
      ),
      jsonb_build_object('outcome', 'observation', 'processRef', '91000000000000000011', 'movements', jsonb_build_array()),
      'provider-payload-v1', '2026-01-01T11:00:00Z', NULL, 12, NULL
    )
  $sql$,
  :'claim_job_id', :'claim_execution_id', :'claim_lease_token', :'claim_correlation_id'
  ),
  'conclusão de observation grava exchange, payload, snapshot, execução e job atomicamente'
);
RESET ROLE;

SELECT is((SELECT status FROM public.query_job WHERE id = :'claim_job_id'), 'succeeded', 'job de observation termina como succeeded');
SELECT is((SELECT status FROM public.query_execution WHERE id = :'claim_execution_id'), 'succeeded', 'execution de observation termina como succeeded');
SELECT is((SELECT count(*)::integer FROM public.process_snapshot WHERE query_execution_id = :'claim_execution_id'), 1, 'observation válida cria exatamente um snapshot');
SELECT is((SELECT count(*)::integer FROM public.raw_provider_payload WHERE provider_exchange_id = (SELECT provider_exchange_id FROM public.query_execution WHERE id = :'claim_execution_id')), 1, 'payload bruto fica ligado à exchange sem duplicação');
SELECT is((SELECT metadata->>'origin' FROM public.audit_log WHERE entity_id = (SELECT id FROM public.process_snapshot WHERE query_execution_id = :'claim_execution_id') AND action = 'process_snapshot.created'), 'system_worker', 'snapshot é auditado como evento sistêmico sem usuário fictício');

SET ROLE service_role;
SELECT is((SELECT public.phase9_scheduler_tick('2026-01-08T11:00:00Z', 300)), 1, 'nova janela cria novo job lógico');
SELECT * FROM public.phase9_claim_query_job('phase9-worker-stale', 15001) \gset stale_
SELECT ok(:'stale_job_id' IS NOT NULL, 'worker recebe job para teste de lease');
SELECT pg_sleep(16);
SELECT is((SELECT public.phase9_recover_expired_query_jobs(10)), 1, 'lease expirada é recuperada');
SELECT lives_ok(
  format($sql$SELECT * FROM public.phase9_complete_query_execution(%L, %L, %L, 'failure', 'timeout', 'datajud_timeout', NULL, NULL, NULL, now(), NULL, 5, NULL)$sql$, :'stale_job_id', :'stale_execution_id', :'stale_lease_token'),
  'worker stale não derruba a transação ao tentar concluir após recovery'
);
RESET ROLE;
SELECT is((SELECT status FROM public.query_job WHERE id = :'stale_job_id'), 'retry_scheduled', 'job recuperado recebe retry_scheduled');
SELECT pg_sleep(2);
SET ROLE service_role;
SELECT * FROM public.phase9_claim_query_job('phase9-worker-retry', 30000) \gset retry_
SELECT ok(:'retry_job_id' IS NOT NULL, 'job recuperado pode ser reivindicado novamente');
SELECT lives_ok(
  format($sql$SELECT * FROM public.phase9_complete_query_execution(%L, %L, %L, 'failure', 'not_found', 'datajud_not_found', NULL, NULL, NULL, now(), 404, 5, NULL)$sql$, :'retry_job_id', :'retry_execution_id', :'retry_lease_token'),
  'not_found conclui sem retry infinito'
);
RESET ROLE;
SELECT is((SELECT status FROM public.query_job WHERE id = :'retry_job_id'), 'terminal_failure', 'not_found termina explicitamente sem comparação');
SELECT is((SELECT count(*)::integer FROM public.query_execution WHERE query_job_id = :'retry_job_id'), 2, 'cada tentativa permanece preservada no histórico');
SELECT is((SELECT count(*)::integer FROM public.process_snapshot WHERE query_execution_id = :'retry_execution_id'), 0, 'falha não cria snapshot');
