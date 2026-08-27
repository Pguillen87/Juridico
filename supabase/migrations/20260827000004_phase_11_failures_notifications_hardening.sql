SET lock_timeout = '2s';

-- Phase 11 post-publication hardening. The historical 00003 remains immutable.
-- These replacements preserve the final behavior already validated on the branch.

CREATE OR REPLACE FUNCTION public.phase11_block_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase11_internal', true) <> '1' THEN
    RAISE EXCEPTION '% is append-only and writable only by internal phase 11 functions', TG_TABLE_NAME
      USING ERRCODE = '42501', HINT = 'Use the authorized domain command.';
  END IF;
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION '% is append-only and has no physical mutation', TG_TABLE_NAME USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_record_failure_event_internal(
  p_office_id UUID,
  p_process_id UUID,
  p_origin TEXT,
  p_provider_id TEXT,
  p_capability TEXT,
  p_failure_stage TEXT,
  p_failure_class TEXT,
  p_failure_code TEXT,
  p_context_allowlisted JSONB,
  p_query_execution_id UUID DEFAULT NULL,
  p_query_job_id UUID DEFAULT NULL,
  p_provider_exchange_id UUID DEFAULT NULL,
  p_attempt_number INTEGER DEFAULT NULL,
  p_source_type TEXT DEFAULT 'persistence',
  p_source_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  incident_row public.failure_incident%ROWTYPE;
  occurrence_id UUID;
  reopened_occurrence_id UUID;
  fingerprint_value TEXT;
  recovery_value TEXT;
  failure_event_key TEXT;
  reopened_event_key TEXT;
  priority_value TEXT;
  job_status_value TEXT;
  metadata JSONB;
  context_key TEXT;
BEGIN
  IF current_user NOT IN ('service_role', 'postgres')
     AND current_setting('juridico.phase11_internal', true) <> '1' THEN
    RAISE EXCEPTION 'phase 11 failure recorder is backend-only' USING ERRCODE = '42501';
  END IF;
  IF p_office_id IS NULL OR p_origin NOT IN (
       'provider', 'query_execution', 'comparison', 'scheduler',
       'worker', 'persistence', 'notification'
     ) OR p_failure_stage NOT IN (
       'provider', 'persistence', 'comparison', 'scheduler', 'worker', 'notification'
     ) OR p_failure_class NOT IN (
       'provider_transient', 'provider_permanent', 'provider_manual_review',
       'persistence', 'comparison', 'scheduler', 'worker', 'notification'
     ) OR p_failure_code NOT IN (
       'provider_not_registered', 'capability_not_supported', 'operation_not_supported',
       'manual_evidence_missing', 'manual_process_mismatch', 'timeout',
       'datajud_input_schema_invalid', 'datajud_timeout', 'datajud_dns_failure',
       'datajud_network_failure', 'datajud_rate_limited', 'datajud_source_unavailable',
       'datajud_not_found', 'datajud_http_failure', 'datajud_payload_too_large',
       'datajud_schema_invalid', 'datajud_process_mismatch',
       'datajud_process_not_eligible', 'datajud_payload_sanitization_failed',
       'provider_persistence_failed', 'provider_backend_unauthorized',
       'provider_backend_unavailable', 'worker_provider_execution_failed',
       'worker_lease_expired', 'comparison_persistence_failed', 'scheduler_failure',
       'worker_failure', 'outbox_persistence_failed', 'audit_failure',
       'not_found', 'not_supported', 'manual_review_required'
     ) OR p_source_type NOT IN (
       'query_execution', 'query_job', 'provider_exchange', 'process_comparison',
       'detected_change', 'scheduler', 'worker', 'persistence', 'incident'
     ) OR p_context_allowlisted IS NULL
     OR jsonb_typeof(p_context_allowlisted) <> 'object' THEN
    RAISE EXCEPTION 'invalid phase 11 failure event input' USING ERRCODE = '22023';
  END IF;
  IF p_process_id IS NULL AND p_origin NOT IN ('scheduler', 'worker', 'persistence', 'notification') THEN
    RAISE EXCEPTION 'process is required for this failure origin' USING ERRCODE = '22023';
  END IF;
  IF p_process_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.legal_process
     WHERE office_id = p_office_id AND id = p_process_id
  ) THEN
    RAISE EXCEPTION 'process does not belong to failure office' USING ERRCODE = '42501';
  END IF;
  FOR context_key IN SELECT jsonb_object_keys(p_context_allowlisted) LOOP
    IF context_key NOT IN (
      'source', 'capability', 'failure_stage', 'http_status', 'operation',
      'cycle', 'window', 'worker_id', 'normalizer_version'
    ) THEN
      RAISE EXCEPTION 'phase 11 failure context key is not allowlisted'
        USING ERRCODE = '22023';
    END IF;
  END LOOP;
  IF p_source_id IS NOT NULL AND p_source_id !~ '^[A-Za-z0-9._:-]{1,240}$' THEN
    RAISE EXCEPTION 'invalid phase 11 failure source id' USING ERRCODE = '22023';
  END IF;
  IF p_attempt_number IS NOT NULL AND p_attempt_number NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'invalid phase 11 attempt number' USING ERRCODE = '22023';
  END IF;
  IF p_query_execution_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.query_execution e
     WHERE e.office_id = p_office_id AND e.id = p_query_execution_id
       AND (p_process_id IS NULL OR e.process_id = p_process_id)
       AND (p_attempt_number IS NULL OR e.attempt_number = p_attempt_number)
  ) THEN
    RAISE EXCEPTION 'query execution does not belong to failure evidence' USING ERRCODE = '42501';
  END IF;
  IF p_query_job_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.query_job j
     WHERE j.office_id = p_office_id AND j.id = p_query_job_id
       AND (p_process_id IS NULL OR j.process_id = p_process_id)
  ) THEN
    RAISE EXCEPTION 'query job does not belong to failure evidence' USING ERRCODE = '42501';
  END IF;
  IF p_provider_exchange_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.provider_exchange x
     WHERE x.office_id = p_office_id AND x.id = p_provider_exchange_id
  ) THEN
    RAISE EXCEPTION 'provider exchange does not belong to failure evidence' USING ERRCODE = '42501';
  END IF;

  fingerprint_value := public.phase11_hash_key(
    'failure-v1|' || p_office_id::TEXT || '|' || coalesce(p_process_id::TEXT, '') || '|' ||
    p_origin || '|' || coalesce(p_provider_id, '') || '|' || coalesce(p_capability, '') || '|' ||
    p_failure_stage || '|' || p_failure_class || '|' || p_failure_code || '|' ||
    p_context_allowlisted::TEXT
  );
  recovery_value := public.phase11_hash_key(
    'recovery-v1|' || p_office_id::TEXT || '|' || coalesce(p_process_id::TEXT, '') || '|' ||
    coalesce(p_provider_id, '') || '|' || coalesce(p_capability, '') || '|' || p_failure_stage || '|' ||
    CASE WHEN p_process_id IS NULL THEN p_origin ELSE 'process' END
  );
  failure_event_key := 'failure-observed:' || coalesce(p_source_id, p_query_execution_id::TEXT,
    p_query_job_id::TEXT, public.phase11_hash_key(fingerprint_value || ':' || clock_timestamp()::TEXT));
  reopened_event_key := 'reopened:' || fingerprint_value || ':' || failure_event_key;

  PERFORM set_config('juridico.phase11_internal', '1', true);
  INSERT INTO public.failure_incident (
    office_id, process_id, origin, provider_id, capability, failure_stage,
    failure_class, failure_code, fingerprint, recovery_key, status,
    first_seen_at, last_seen_at, occurrence_count, current_execution_id, current_job_id
  ) VALUES (
    p_office_id, p_process_id, p_origin, p_provider_id, p_capability, p_failure_stage,
    p_failure_class, p_failure_code, fingerprint_value, recovery_value, 'open',
    clock_timestamp(), clock_timestamp(), 0, p_query_execution_id, p_query_job_id
  ) ON CONFLICT (office_id, fingerprint) DO NOTHING;

  SELECT * INTO incident_row
    FROM public.failure_incident
   WHERE office_id = p_office_id AND fingerprint = fingerprint_value
   FOR UPDATE;
  IF incident_row.id IS NULL THEN
    RAISE EXCEPTION 'failure incident could not be created' USING ERRCODE = 'XX000';
  END IF;

  IF incident_row.status = 'resolved' THEN
    UPDATE public.failure_incident
       SET status = 'open', last_seen_at = clock_timestamp(), updated_at = clock_timestamp(),
           resolved_at = NULL, resolved_by = NULL, resolution_kind = NULL,
           resolution_code = NULL, resolution_note_sanitized = NULL,
           current_execution_id = p_query_execution_id, current_job_id = p_query_job_id
     WHERE office_id = p_office_id AND id = incident_row.id;
    INSERT INTO public.failure_occurrence (
      office_id, incident_id, event_kind, process_id, origin, failure_stage,
      failure_class, failure_code, source_type, source_id, recovery_key,
      query_execution_id, query_job_id, provider_exchange_id, attempt_number,
      observed_job_status, sanitized_message_code, context_allowlisted,
      occurrence_idempotency_key
    ) VALUES (
      p_office_id, incident_row.id, 'reopened', p_process_id, p_origin, p_failure_stage,
      p_failure_class, p_failure_code, p_source_type, p_source_id, recovery_value,
      p_query_execution_id, p_query_job_id, p_provider_exchange_id, p_attempt_number,
      NULL, p_failure_code, p_context_allowlisted, reopened_event_key
    ) ON CONFLICT (office_id, occurrence_idempotency_key) DO NOTHING
    RETURNING id INTO reopened_occurrence_id;
    IF reopened_occurrence_id IS NOT NULL THEN
      PERFORM public.phase11_write_operational_audit(
        'failure.incident.reopened', 'failure_occurrence', reopened_occurrence_id,
        p_office_id, NULL,
        jsonb_build_object('after_status', 'open', 'failure_code', p_failure_code,
                           'fingerprint', fingerprint_value, 'recovery_key', recovery_value,
                           'source_type', p_source_type, 'source_id', p_source_id)
      );
      PERFORM public.phase11_enqueue_notification_internal(
        p_office_id, 'incident_reopened', incident_row.id, reopened_occurrence_id, NULL,
        jsonb_build_object('template_version', 'failure.v1', 'event_type', 'incident_reopened',
                           'code', p_failure_code, 'operational_priority', 'high',
                           'incident_id', incident_row.id, 'occurrence_id', reopened_occurrence_id,
                           'process_id', p_process_id)
      );
    END IF;
  END IF;

  SELECT j.status INTO job_status_value
    FROM public.query_job j
   WHERE j.office_id = p_office_id AND j.id = p_query_job_id;
  priority_value := CASE WHEN job_status_value = 'retry_scheduled' THEN 'medium' ELSE 'high' END;
  INSERT INTO public.failure_occurrence (
    office_id, incident_id, event_kind, process_id, origin, failure_stage,
    failure_class, failure_code, source_type, source_id, recovery_key,
    query_execution_id, query_job_id, provider_exchange_id, attempt_number,
    observed_job_status, sanitized_message_code, context_allowlisted,
    occurrence_idempotency_key
  ) VALUES (
    p_office_id, incident_row.id, 'failure_observed', p_process_id, p_origin, p_failure_stage,
    p_failure_class, p_failure_code, p_source_type, p_source_id, recovery_value,
    p_query_execution_id, p_query_job_id, p_provider_exchange_id, p_attempt_number,
    job_status_value, p_failure_code, p_context_allowlisted, failure_event_key
  ) ON CONFLICT (office_id, occurrence_idempotency_key) DO NOTHING
  RETURNING id INTO occurrence_id;
  IF occurrence_id IS NULL THEN
    RETURN incident_row.id;
  END IF;

  UPDATE public.failure_incident
     SET last_seen_at = clock_timestamp(), occurrence_count = occurrence_count + 1,
         current_execution_id = coalesce(p_query_execution_id, current_execution_id),
         current_job_id = coalesce(p_query_job_id, current_job_id),
         updated_at = clock_timestamp()
   WHERE office_id = p_office_id AND id = incident_row.id;

  metadata := jsonb_build_object(
    'failure_code', p_failure_code, 'failure_class', p_failure_class,
    'failure_stage', p_failure_stage, 'origin', p_origin,
    'fingerprint', fingerprint_value, 'recovery_key', recovery_value,
    'attempt_number', p_attempt_number, 'source_type', p_source_type,
    'source_id', p_source_id, 'execution_id', p_query_execution_id,
    'job_id', p_query_job_id, 'process_id', p_process_id
  );
  IF incident_row.created_at >= clock_timestamp() - interval '1 second' THEN
    PERFORM public.phase11_write_operational_audit(
      'failure.incident.created', 'failure_incident', incident_row.id,
      p_office_id, NULL, metadata
    );
  END IF;
  PERFORM public.phase11_write_operational_audit(
    'failure.incident.observed', 'failure_occurrence', occurrence_id,
    p_office_id, NULL, metadata || jsonb_build_object('after_status', 'open')
  );
  PERFORM public.phase11_enqueue_notification_internal(
    p_office_id, 'failure_observed', incident_row.id, occurrence_id, NULL,
    jsonb_build_object('template_version', 'failure.v1', 'event_type', 'failure_observed',
                       'code', p_failure_code, 'operational_priority', priority_value,
                       'incident_id', incident_row.id, 'occurrence_id', occurrence_id,
                       'attempt_number', p_attempt_number, 'process_id', p_process_id)
  );
  RETURN incident_row.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_request_failure_reprocess(
  p_incident_id UUID,
  p_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  incident_row public.failure_incident%ROWTYPE;
  failed_job public.query_job%ROWTYPE;
  new_job_id UUID;
  occurrence_id UUID;
  internal_key TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_incident_id IS NULL OR p_idempotency_key IS NULL
     OR btrim(p_idempotency_key) !~ '^[A-Za-z0-9._:-]{1,120}$' THEN
    RAISE EXCEPTION 'invalid failure reprocess input' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO incident_row
    FROM public.failure_incident
   WHERE id = p_incident_id AND office_id = actor.actor_office_id
   FOR SHARE;
  IF incident_row.id IS NULL OR incident_row.current_job_id IS NULL THEN
    RAISE EXCEPTION 'failure incident has no reprocessable job' USING ERRCODE = '42501';
  END IF;
  SELECT fo.query_job_id INTO new_job_id
    FROM public.failure_occurrence fo
   WHERE fo.office_id = actor.actor_office_id
     AND fo.incident_id = incident_row.id
     AND fo.event_kind = 'manual_reprocess_requested'
     AND fo.occurrence_idempotency_key =
       'manual-reprocess-requested:' || actor.actor_office_id::TEXT || ':' || btrim(p_idempotency_key)
   LIMIT 1;
  IF new_job_id IS NOT NULL THEN
    RETURN new_job_id;
  END IF;
  internal_key := 'manual-reprocess:' || incident_row.current_job_id::TEXT || ':' || btrim(p_idempotency_key);
  SELECT id INTO new_job_id
    FROM public.query_job
   WHERE office_id = actor.actor_office_id AND idempotency_key = internal_key;
  IF new_job_id IS NOT NULL THEN
    RETURN new_job_id;
  END IF;
  SELECT * INTO failed_job
    FROM public.query_job
   WHERE id = incident_row.current_job_id
     AND office_id = actor.actor_office_id
   FOR SHARE;
  IF failed_job.id IS NULL OR failed_job.status <> 'terminal_failure' THEN
    RAISE EXCEPTION 'job is not eligible for failure reprocess' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.legal_process lp
     WHERE lp.id = failed_job.process_id
       AND lp.office_id = actor.actor_office_id
       AND lp.status = 'active'
       AND lp.is_public = true
  ) THEN
    RAISE EXCEPTION 'process is not eligible for failure reprocess' USING ERRCODE = '42501';
  END IF;
  internal_key := 'manual-reprocess:' || failed_job.id::TEXT || ':' || btrim(p_idempotency_key);
  PERFORM set_config('juridico.phase11_internal', '1', true);
  PERFORM public.phase9_request_manual_reprocess(failed_job.id, btrim(p_idempotency_key));
  SELECT id INTO new_job_id FROM public.query_job
   WHERE office_id = actor.actor_office_id AND idempotency_key = internal_key;
  IF new_job_id IS NULL THEN
    RAISE EXCEPTION 'manual reprocess job was not created' USING ERRCODE = 'XX000';
  END IF;
  PERFORM set_config('juridico.phase11_internal', '1', true);
  UPDATE public.failure_incident
     SET current_job_id = new_job_id, updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = incident_row.id;
  INSERT INTO public.failure_occurrence (
    office_id, incident_id, event_kind, process_id, origin, failure_stage,
    failure_class, failure_code, source_type, source_id, recovery_key,
    query_job_id, sanitized_message_code, context_allowlisted,
    occurrence_idempotency_key, event_actor_user_id
  ) VALUES (
    actor.actor_office_id, incident_row.id, 'manual_reprocess_requested',
    incident_row.process_id, incident_row.origin, incident_row.failure_stage,
    incident_row.failure_class, incident_row.failure_code, 'query_job', new_job_id::TEXT,
    incident_row.recovery_key, new_job_id, 'manual_reprocess_requested',
    jsonb_build_object('operation', 'failure_reprocess'),
    'manual-reprocess-requested:' || actor.actor_office_id::TEXT || ':' || btrim(p_idempotency_key),
    actor.actor_id
  ) ON CONFLICT (office_id, occurrence_idempotency_key) DO NOTHING
  RETURNING id INTO occurrence_id;
  IF occurrence_id IS NOT NULL THEN
    PERFORM public.phase11_write_operational_audit(
      'failure.incident.manual_reprocess_requested', 'failure_occurrence', occurrence_id,
      actor.actor_office_id, actor.actor_id,
      jsonb_build_object('job_id', new_job_id, 'idempotency_key', btrim(p_idempotency_key),
                         'source_type', 'query_job')
    );
  END IF;
  RETURN new_job_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.phase11_record_failure_event_internal(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID, UUID, UUID, INTEGER, TEXT, TEXT) TO service_role;
