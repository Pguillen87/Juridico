-- Fase 11: substitui RECORDs sem tipo nas funções internas apontadas pelo
-- lint do Supabase. A migration é aditiva e preserva as assinaturas públicas,
-- grants, auditoria, idempotência e isolamento da implementação histórica.

CREATE OR REPLACE FUNCTION public.phase11_record_execution_failure_internal(
  p_execution_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  execution_row public.query_execution%ROWTYPE;
  job_status_value public.query_job.status%TYPE;
  class_value TEXT;
  context_value JSONB;
BEGIN
  IF p_execution_id IS NULL THEN
    RAISE EXCEPTION 'execution id is required' USING ERRCODE = '22023';
  END IF;

  SELECT qe.*
    INTO execution_row
    FROM public.query_execution qe
    JOIN public.query_job qj
      ON qj.office_id = qe.office_id
     AND qj.id = qe.query_job_id
   WHERE qe.id = p_execution_id;

  SELECT qj.status
    INTO job_status_value
    FROM public.query_job qj
   WHERE qj.office_id = execution_row.office_id
     AND qj.id = execution_row.query_job_id;

  IF execution_row.id IS NULL OR job_status_value IS NULL THEN
    RAISE EXCEPTION 'query execution not found' USING ERRCODE = '42501';
  END IF;
  IF execution_row.error_code IS NULL
     OR execution_row.status NOT IN ('retry_scheduled', 'terminal_failure', 'cancelled') THEN
    RETURN NULL;
  END IF;

  class_value := public.phase11_failure_class(execution_row.error_code);
  context_value := jsonb_build_object(
    'source', 'datajud', 'capability', execution_row.capability,
    'failure_stage', 'provider', 'http_status', execution_row.http_status
  );
  PERFORM set_config('juridico.phase11_internal', '1', true);
  RETURN public.phase11_record_failure_event_internal(
    execution_row.office_id, execution_row.process_id, 'provider',
    execution_row.provider_id, execution_row.capability, 'provider', class_value,
    execution_row.error_code, context_value, execution_row.id,
    execution_row.query_job_id, execution_row.provider_exchange_id,
    execution_row.attempt_number, 'query_execution', execution_row.id::TEXT
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_reconcile_success_internal(
  p_execution_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  execution_row public.query_execution%ROWTYPE;
  incident_row public.failure_incident%ROWTYPE;
  occurrence_id UUID;
  recovery_value TEXT;
  resolved_count INTEGER := 0;
BEGIN
  IF p_execution_id IS NULL THEN
    RAISE EXCEPTION 'execution id is required' USING ERRCODE = '22023';
  END IF;

  SELECT qe.*
    INTO execution_row
    FROM public.query_execution qe
   WHERE qe.id = p_execution_id;

  IF execution_row.id IS NULL
     OR execution_row.status <> 'succeeded'
     OR NOT EXISTS (
       SELECT 1
         FROM public.process_snapshot ps
        WHERE ps.office_id = execution_row.office_id
          AND ps.query_execution_id = execution_row.id
     ) THEN
    RETURN 0;
  END IF;

  recovery_value := public.phase11_hash_key(
    'recovery-v1|' || execution_row.office_id::TEXT || '|' ||
    execution_row.process_id::TEXT || '|' || execution_row.provider_id || '|' ||
    execution_row.capability || '|provider|process'
  );
  PERFORM set_config('juridico.phase11_internal', '1', true);

  FOR incident_row IN
    SELECT fi.*
      FROM public.failure_incident fi
     WHERE fi.office_id = execution_row.office_id
       AND fi.process_id = execution_row.process_id
       AND fi.recovery_key = recovery_value
       AND fi.status = 'open'
       AND fi.failure_class = 'provider_transient'
       AND fi.failure_code NOT IN ('manual_review_required', 'not_found', 'not_supported')
     FOR UPDATE
  LOOP
    INSERT INTO public.failure_occurrence (
      office_id, incident_id, event_kind, process_id, origin, failure_stage,
      failure_class, source_type, source_id, recovery_key, query_execution_id,
      query_job_id, attempt_number, observed_job_status, sanitized_message_code,
      context_allowlisted, occurrence_idempotency_key
    ) VALUES (
      execution_row.office_id, incident_row.id, 'auto_resolved',
      execution_row.process_id, 'provider', 'provider', incident_row.failure_class,
      'query_execution', execution_row.id::TEXT, recovery_value, execution_row.id,
      execution_row.query_job_id, execution_row.attempt_number, 'succeeded',
      'successful_observation',
      jsonb_build_object('source', 'datajud', 'capability', execution_row.capability),
      'auto-resolved:' || incident_row.id::TEXT || ':' || execution_row.id::TEXT
    ) ON CONFLICT (office_id, occurrence_idempotency_key) DO NOTHING
    RETURNING id INTO occurrence_id;

    IF occurrence_id IS NULL THEN
      CONTINUE;
    END IF;

    UPDATE public.failure_incident
       SET status = 'resolved', resolution_kind = 'auto_recovered',
           resolution_code = 'successful_observation', resolved_at = clock_timestamp(),
           resolved_by = NULL, resolution_note_sanitized = NULL,
           updated_at = clock_timestamp()
     WHERE office_id = execution_row.office_id
       AND id = incident_row.id;

    PERFORM public.phase11_write_operational_audit(
      'failure.incident.auto_resolved', 'failure_occurrence', occurrence_id,
      execution_row.office_id, NULL,
      jsonb_build_object(
        'after_status', 'resolved', 'resolution_code', 'successful_observation',
        'recovery_key', recovery_value, 'execution_id', execution_row.id,
        'attempt_number', execution_row.attempt_number
      )
    );
    PERFORM public.phase11_enqueue_notification_internal(
      execution_row.office_id, 'incident_auto_resolved', incident_row.id,
      occurrence_id, NULL,
      jsonb_build_object(
        'template_version', 'failure.v1', 'event_type', 'incident_auto_resolved',
        'code', 'successful_observation', 'operational_priority', 'low',
        'incident_id', incident_row.id, 'occurrence_id', occurrence_id,
        'attempt_number', execution_row.attempt_number,
        'process_id', execution_row.process_id
      )
    );
    resolved_count := resolved_count + 1;
  END LOOP;
  RETURN resolved_count;
END;
$$;

REVOKE ALL ON FUNCTION public.phase11_record_execution_failure_internal(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase11_reconcile_success_internal(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phase11_record_execution_failure_internal(UUID)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.phase11_reconcile_success_internal(UUID)
  TO service_role;
