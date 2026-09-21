-- Realinhamento 1: Consulta Real Controlada, manual refresh e targeted claim.
-- Migration aditiva e retrocompatível.
SET lock_timeout = '2s';

-- 1. Relax check constraints to permit datajud_public and manual_refresh
ALTER TABLE public.provider_exchange
  DROP CONSTRAINT IF EXISTS provider_exchange_provider_id_check;
ALTER TABLE public.provider_exchange
  ADD CONSTRAINT provider_exchange_provider_id_check
  CHECK (provider_id IN ('datajud_sandbox', 'datajud_public', 'manual_observation'));

ALTER TABLE public.provider_exchange
  DROP CONSTRAINT IF EXISTS provider_exchange_check;
ALTER TABLE public.provider_exchange
  ADD CONSTRAINT provider_exchange_check
  CHECK (
    (result_kind = 'observation' AND result_status = 'observed' AND error_code IS NULL AND normalized_result IS NOT NULL)
    OR
    (result_kind = 'failure' AND result_status <> 'observed' AND error_code IS NOT NULL AND normalized_result IS NULL)
  );

ALTER TABLE public.raw_provider_payload
  DROP CONSTRAINT IF EXISTS raw_provider_payload_provider_id_check;
ALTER TABLE public.raw_provider_payload
  ADD CONSTRAINT raw_provider_payload_provider_id_check
  CHECK (provider_id IN ('datajud_sandbox', 'datajud_public', 'manual_observation'));

ALTER TABLE public.query_job
  DROP CONSTRAINT IF EXISTS query_job_provider_id_check;
ALTER TABLE public.query_job
  ADD CONSTRAINT query_job_provider_id_check
  CHECK (provider_id IN ('datajud_sandbox', 'datajud_public'));

ALTER TABLE public.query_job
  DROP CONSTRAINT IF EXISTS query_job_job_kind_check;
ALTER TABLE public.query_job
  ADD CONSTRAINT query_job_job_kind_check
  CHECK (job_kind IN ('scheduled', 'manual_reprocess', 'manual_refresh'));

ALTER TABLE public.query_job
  DROP CONSTRAINT IF EXISTS query_job_check;
ALTER TABLE public.query_job
  ADD CONSTRAINT query_job_check
  CHECK (
    (job_kind = 'scheduled' AND scheduled_window_utc IS NOT NULL)
    OR (job_kind IN ('manual_reprocess', 'manual_refresh') AND scheduled_window_utc IS NULL)
  );

ALTER TABLE public.query_execution
  DROP CONSTRAINT IF EXISTS query_execution_provider_id_check;
ALTER TABLE public.query_execution
  ADD CONSTRAINT query_execution_provider_id_check
  CHECK (provider_id IN ('datajud_sandbox', 'datajud_public'));

ALTER TABLE public.process_snapshot
  DROP CONSTRAINT IF EXISTS process_snapshot_provider_id_check;
ALTER TABLE public.process_snapshot
  ADD CONSTRAINT process_snapshot_provider_id_check
  CHECK (provider_id IN ('datajud_sandbox', 'datajud_public'));

-- 2. Partial unique index to guarantee single active manual_refresh job per process and provider
CREATE UNIQUE INDEX IF NOT EXISTS query_job_single_active_manual_refresh_idx
  ON public.query_job (office_id, process_id, provider_id)
  WHERE status IN ('pending', 'running', 'retry_scheduled') AND job_kind = 'manual_refresh';

-- 3. Update phase9_write_user_audit to allow manual_refresh audit events
CREATE OR REPLACE FUNCTION public.phase9_write_user_audit(
  p_action TEXT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  audit_id BIGINT;
  metadata_key TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN (
    'process.monitoring.updated',
    'query_job.manual_reprocess_requested',
    'query_job.manual_refresh_requested'
  ) THEN
    RAISE EXCEPTION 'phase 9 user audit action is not allowlisted' USING ERRCODE = '22023';
  END IF;
  IF (p_action = 'process.monitoring.updated' AND p_entity_type <> 'legal_process')
     OR (p_action IN ('query_job.manual_reprocess_requested', 'query_job.manual_refresh_requested') AND p_entity_type <> 'query_job') THEN
    RAISE EXCEPTION 'phase 9 user audit entity mismatch' USING ERRCODE = '22023';
  END IF;
  IF p_metadata IS NULL OR jsonb_typeof(p_metadata) <> 'object' THEN
    RAISE EXCEPTION 'invalid phase 9 user audit metadata' USING ERRCODE = '22023';
  END IF;
  FOR metadata_key IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF metadata_key NOT IN (
      'before_status', 'after_status', 'failed_job_id', 'idempotency_key',
      'process_id', 'provider_id', 'correlation_id', 'job_id', 'timestamp'
    ) THEN
      RAISE EXCEPTION 'phase 9 user audit metadata key is not allowlisted'
        USING ERRCODE = '22023';
    END IF;
  END LOOP;
  INSERT INTO public.audit_log (
    audit_scope, office_id, actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    'operational', actor.actor_office_id, actor.actor_id, p_action,
    p_entity_type, p_entity_id, p_metadata
  ) RETURNING id INTO audit_id;
  RETURN audit_id;
END;
$$;

-- 4. Update phase9_claim_query_job to allow manual_refresh
CREATE OR REPLACE FUNCTION public.phase9_claim_query_job(
  p_worker_id TEXT,
  p_lease_duration_ms INTEGER DEFAULT 30000
)
RETURNS TABLE (
  job_id UUID,
  execution_id UUID,
  office_id UUID,
  process_id UUID,
  provider_id TEXT,
  capability TEXT,
  job_kind TEXT,
  subject_ref TEXT,
  request_fingerprint TEXT,
  correlation_id TEXT,
  attempt_number INTEGER,
  lease_token UUID,
  lease_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  job_row public.query_job%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  execution_uuid UUID;
  token UUID;
  expires_at TIMESTAMPTZ;
  execution_correlation TEXT;
BEGIN
  IF p_worker_id IS NULL OR p_worker_id !~ '^[A-Za-z0-9._:-]{1,120}$'
     OR p_lease_duration_ms <= 15000 OR p_lease_duration_ms > 120000 THEN
    RAISE EXCEPTION 'invalid worker claim input' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('juridico.phase9_internal', '1', true);
  SELECT j.* INTO job_row
    FROM public.query_job j
   WHERE j.status IN ('pending', 'retry_scheduled')
     AND j.available_at <= clock_timestamp()
     AND j.attempt_count < j.max_attempts
   ORDER BY j.available_at, j.created_at, j.id
   LIMIT 1
   FOR UPDATE SKIP LOCKED;
  IF job_row.id IS NULL THEN
    RETURN;
  END IF;
  SELECT lp.* INTO process_row
    FROM public.legal_process lp
   WHERE lp.id = job_row.process_id
     AND lp.office_id = job_row.office_id
   FOR SHARE;
  IF process_row.id IS NULL OR process_row.status <> 'active'
     OR process_row.is_public IS DISTINCT FROM true
     OR (job_row.job_kind = 'scheduled' AND process_row.monitoring_status <> 'active') THEN
    UPDATE public.query_job
       SET status = 'terminal_failure',
           last_error_code = 'process_not_eligible',
           last_error_message = 'Processo não elegível para monitoramento.',
           finished_at = clock_timestamp(),
           updated_at = clock_timestamp(),
           available_at = clock_timestamp()
     WHERE id = job_row.id;
    PERFORM public.phase9_write_system_audit(
      'query_job.terminal_failure', 'query_job', job_row.id, job_row.office_id,
      jsonb_build_object('error_code', 'process_not_eligible', 'reason', 'pre_claim_guard'),
      'system_worker', p_worker_id
    );
    RETURN;
  END IF;
  token := gen_random_uuid();
  expires_at := clock_timestamp() + (p_lease_duration_ms * INTERVAL '1 millisecond');
  UPDATE public.query_job
     SET status = 'running',
         attempt_count = attempt_count + 1,
         lease_token = token,
         lease_expires_at = expires_at,
         locked_by = p_worker_id,
         updated_at = clock_timestamp()
   WHERE id = job_row.id
     AND status IN ('pending', 'retry_scheduled')
   RETURNING * INTO job_row;
  execution_correlation := job_row.correlation_id || ':attempt:' || job_row.attempt_count::TEXT;
  INSERT INTO public.query_execution (
    office_id, query_job_id, process_id, provider_id, capability,
    attempt_number, status, correlation_id
  ) VALUES (
    job_row.office_id, job_row.id, job_row.process_id, job_row.provider_id,
    job_row.capability, job_row.attempt_count, 'running', execution_correlation
  ) RETURNING id INTO execution_uuid;
  PERFORM public.phase9_write_system_audit(
    'query_job.claimed', 'query_job', job_row.id, job_row.office_id,
    jsonb_build_object('attempt_number', job_row.attempt_count),
    'system_worker', p_worker_id
  );
  PERFORM public.phase9_write_system_audit(
    'query_execution.started', 'query_execution', execution_uuid, job_row.office_id,
    jsonb_build_object('attempt_number', job_row.attempt_count),
    'system_worker', p_worker_id
  );
  job_id := job_row.id;
  execution_id := execution_uuid;
  office_id := job_row.office_id;
  process_id := job_row.process_id;
  provider_id := job_row.provider_id;
  capability := job_row.capability;
  job_kind := job_row.job_kind;
  subject_ref := process_row.cnj_number;
  request_fingerprint := job_row.request_fingerprint;
  correlation_id := execution_correlation;
  attempt_number := job_row.attempt_count;
  lease_token := token;
  lease_expires_at := expires_at;
  RETURN NEXT;
END;
$$;

-- 3. Update phase9_complete_query_execution to accept datajud_public and manual_refresh
CREATE OR REPLACE FUNCTION public.phase9_complete_query_execution(
  p_job_id UUID,
  p_execution_id UUID,
  p_lease_token UUID,
  p_result_kind TEXT,
  p_result_status TEXT,
  p_error_code TEXT DEFAULT NULL,
  p_normalized_result JSONB DEFAULT NULL,
  p_raw_payload JSONB DEFAULT NULL,
  p_sanitization_version TEXT DEFAULT NULL,
  p_received_at TIMESTAMPTZ DEFAULT now(),
  p_http_status INTEGER DEFAULT NULL,
  p_duration_ms INTEGER DEFAULT NULL,
  p_retry_after_ms INTEGER DEFAULT NULL
)
RETURNS TABLE (
  job_id UUID,
  execution_id UUID,
  job_status TEXT,
  exchange_id UUID,
  snapshot_id UUID,
  next_attempt_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  job_row public.query_job%ROWTYPE;
  execution_row public.query_execution%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  exchange_uuid UUID;
  payload_uuid UUID;
  snapshot_uuid UUID;
  payload_hash TEXT;
  payload_bytes INTEGER;
  next_status TEXT;
  retry_delay_ms INTEGER;
  retry_at TIMESTAMPTZ;
  retryable BOOLEAN;
  normalized_data JSONB;
  missing_fields JSONB;
BEGIN
  IF p_job_id IS NULL OR p_execution_id IS NULL OR p_lease_token IS NULL
     OR p_result_kind IS NULL OR p_result_status IS NULL
     OR p_duration_ms IS NULL OR p_duration_ms < 0 OR p_duration_ms > 86400000
     OR p_http_status IS NOT NULL AND (p_http_status < 100 OR p_http_status > 599)
     OR p_retry_after_ms IS NOT NULL AND (p_retry_after_ms < 0 OR p_retry_after_ms > 600000)
  THEN
    RAISE EXCEPTION 'invalid query execution completion input' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('juridico.phase9_internal', '1', true);
  SELECT * INTO job_row
    FROM public.query_job
   WHERE id = p_job_id
   FOR UPDATE;
  IF job_row.id IS NULL THEN
    RAISE EXCEPTION 'query job not found' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO execution_row
    FROM public.query_execution
   WHERE id = p_execution_id AND query_job_id = p_job_id
   FOR UPDATE;
  IF execution_row.id IS NULL THEN
    RAISE EXCEPTION 'query execution not found' USING ERRCODE = '42501';
  END IF;
  IF job_row.status = 'running' AND execution_row.status <> 'running' THEN
    RAISE EXCEPTION 'query execution lease is no longer active'
      USING ERRCODE = '42501';
  END IF;
  IF job_row.status <> 'running' OR execution_row.status <> 'running' THEN
    SELECT job_row.id, execution_row.id, job_row.status,
           execution_row.provider_exchange_id,
           (SELECT ps.id FROM public.process_snapshot ps WHERE ps.query_execution_id = execution_row.id),
           NULL::TIMESTAMPTZ
      INTO job_id, execution_id, job_status, exchange_id, snapshot_id, next_attempt_at;
    RETURN NEXT;
    RETURN;
  END IF;
  IF job_row.lease_token IS DISTINCT FROM p_lease_token
     OR job_row.lease_expires_at IS NULL
     OR job_row.lease_expires_at <= clock_timestamp()
  THEN
    RAISE EXCEPTION 'query job lease is not valid' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO process_row
    FROM public.legal_process
   WHERE id = job_row.process_id AND office_id = job_row.office_id
   FOR SHARE;
  IF process_row.id IS NULL OR process_row.status <> 'active'
     OR process_row.is_public IS DISTINCT FROM true
     OR (job_row.job_kind = 'scheduled' AND process_row.monitoring_status <> 'active')
  THEN
    RAISE EXCEPTION 'process is no longer eligible for provider observation'
      USING ERRCODE = '42501';
  END IF;
  IF p_result_kind NOT IN ('observation', 'failure') THEN
    RAISE EXCEPTION 'invalid provider result kind' USING ERRCODE = '22023';
  END IF;
  IF p_result_status NOT IN (
    'observed', 'not_found', 'not_supported', 'rate_limited', 'timeout',
    'source_unavailable', 'technical_failure', 'manual_review_required'
  ) THEN
    RAISE EXCEPTION 'invalid provider result status' USING ERRCODE = '22023';
  END IF;
  IF p_result_kind = 'observation' AND (
       p_result_status <> 'observed' OR p_error_code IS NOT NULL
       OR p_normalized_result IS NULL
       OR jsonb_typeof(p_normalized_result) <> 'object'
       OR public.provider_json_has_comparison(p_normalized_result)
       OR public.provider_payload_has_sensitive_key(p_normalized_result)
       OR p_normalized_result->>'kind' <> 'observation'
       OR p_normalized_result->>'status' <> 'observed'
       OR p_normalized_result->'provider'->>'providerId' <> job_row.provider_id
       OR p_normalized_result->>'source' <> 'datajud'
       OR p_normalized_result->>'contractVersion' <> '1'
       OR p_normalized_result->>'correlationId' <> execution_row.correlation_id
       OR p_normalized_result->'data'->>'processRef' <> process_row.cnj_number
     )
  THEN
    RAISE EXCEPTION 'invalid normalized provider observation' USING ERRCODE = '22023';
  END IF;
  IF p_result_kind = 'failure' AND (
       p_result_status = 'observed' OR p_error_code IS NULL
       OR p_normalized_result IS NOT NULL
       OR p_error_code NOT IN (
         'datajud_not_found', 'datajud_rate_limited', 'datajud_timeout',
         'datajud_source_unavailable', 'datajud_dns_failure',
         'datajud_network_failure', 'datajud_http_failure',
         'datajud_schema_invalid', 'datajud_payload_too_large',
         'datajud_process_mismatch', 'datajud_input_schema_invalid',
         'datajud_payload_sanitization_failed', 'provider_persistence_failed',
         'worker_provider_execution_failed', 'datajud_movement_ambiguity_detected',
         'datajud_auth_failure', 'datajud_endpoint_not_supported',
         'datajud_multiple_hits_returned', 'datajud_not_configured'
       )
     )
  THEN
    RAISE EXCEPTION 'invalid provider failure' USING ERRCODE = '22023';
  END IF;
  IF p_raw_payload IS NOT NULL THEN
    IF jsonb_typeof(p_raw_payload) NOT IN ('object', 'array')
       OR public.provider_payload_has_sensitive_key(p_raw_payload)
       OR public.provider_json_has_comparison(p_raw_payload)
    THEN
      RAISE EXCEPTION 'raw provider payload is not safe to persist' USING ERRCODE = '22023';
    END IF;
    payload_bytes := octet_length(convert_to(p_raw_payload::TEXT, 'UTF8'));
    IF payload_bytes < 1 OR payload_bytes > 262144 THEN
      RAISE EXCEPTION 'raw provider payload exceeds the maximum size' USING ERRCODE = '22023';
    END IF;
    payload_hash := encode(extensions.digest(convert_to(p_raw_payload::TEXT, 'UTF8'), 'sha256'), 'hex');
    IF p_sanitization_version IS NULL OR char_length(btrim(p_sanitization_version)) NOT BETWEEN 1 AND 80 THEN
      RAISE EXCEPTION 'sanitization version is required' USING ERRCODE = '22023';
    END IF;
  ELSIF p_sanitization_version IS NOT NULL THEN
    RAISE EXCEPTION 'sanitization version requires a raw payload' USING ERRCODE = '22023';
  END IF;
  IF p_result_kind = 'observation' THEN
    normalized_data := p_normalized_result->'data';
    missing_fields := coalesce(p_normalized_result->'missingFields', '[]'::jsonb);
    IF jsonb_typeof(normalized_data) <> 'object' OR jsonb_typeof(missing_fields) <> 'array' THEN
      RAISE EXCEPTION 'invalid snapshot data' USING ERRCODE = '22023';
    END IF;
  END IF;
  INSERT INTO public.provider_exchange (
    office_id, process_id, provider_id, source, contract_version,
    subject_ref, correlation_id, request_fingerprint, result_kind,
    result_status, error_code, normalized_result
  ) VALUES (
    job_row.office_id, job_row.process_id, job_row.provider_id, 'datajud', 1,
    process_row.cnj_number, execution_row.correlation_id, job_row.request_fingerprint,
    p_result_kind, p_result_status, nullif(btrim(p_error_code), ''),
    CASE WHEN p_result_kind = 'observation' THEN p_normalized_result ELSE NULL END
  ) RETURNING id INTO exchange_uuid;
  PERFORM public.phase9_write_system_audit(
    'provider.exchange.recorded', 'provider_exchange', exchange_uuid, job_row.office_id,
    jsonb_build_object(
      'provider_id', job_row.provider_id, 'result_kind', p_result_kind,
      'status', p_result_status, 'error_code', nullif(btrim(p_error_code), '')
    ) - 'error_code',
    'system_worker', job_row.locked_by
  );
  IF p_raw_payload IS NOT NULL THEN
    INSERT INTO public.raw_provider_payload (
      provider_exchange_id, office_id, process_id, provider_id, source,
      correlation_id, sanitization_version, payload, payload_hash,
      payload_bytes, received_at
    ) VALUES (
      exchange_uuid, job_row.office_id, job_row.process_id, job_row.provider_id,
      'datajud', execution_row.correlation_id, btrim(p_sanitization_version),
      p_raw_payload, payload_hash, payload_bytes, coalesce(p_received_at, now())
    ) RETURNING id INTO payload_uuid;
    PERFORM public.phase9_write_system_audit(
      'provider.payload.recorded', 'raw_provider_payload', payload_uuid, job_row.office_id,
      jsonb_build_object('provider_id', job_row.provider_id,
                         'payload_hash', payload_hash,
                         'payload_bytes', payload_bytes),
      'system_worker', job_row.locked_by
    );
  END IF;
  IF p_result_kind = 'observation' THEN
    INSERT INTO public.process_snapshot (
      office_id, process_id, query_execution_id, provider_id, source,
      normalizer_version, normalized_data, missing_fields, snapshot_hash, evidence_ref
    ) VALUES (
      job_row.office_id, job_row.process_id, execution_row.id, job_row.provider_id,
      'datajud',
      coalesce(p_normalized_result->'provider'->>'adapterVersion', 'provider-contract-v1'),
      normalized_data, missing_fields,
      encode(extensions.digest(convert_to(normalized_data::TEXT, 'UTF8'), 'sha256'), 'hex'),
      p_normalized_result->'evidence'->>'evidenceRef'
    ) RETURNING id, snapshot_hash INTO snapshot_uuid, payload_hash;
    PERFORM public.phase9_write_system_audit(
      'process_snapshot.created', 'process_snapshot', snapshot_uuid, job_row.office_id,
      jsonb_build_object('snapshot_hash', payload_hash),
      'system_worker', job_row.locked_by
    );
  END IF;
  retryable := p_result_kind = 'failure'
    AND p_result_status IN ('rate_limited', 'timeout', 'source_unavailable');
  IF p_result_kind = 'observation' THEN
    next_status := 'succeeded';
    retry_at := NULL;
  ELSIF retryable AND job_row.attempt_count < job_row.max_attempts THEN
    retry_delay_ms := least(
      60000,
      greatest(
        1000 * (2 ^ greatest(job_row.attempt_count - 1, 0)),
        coalesce(p_retry_after_ms, 0)
      )
    );
    retry_at := clock_timestamp() + (retry_delay_ms * INTERVAL '1 millisecond');
    next_status := 'retry_scheduled';
  ELSE
    retry_at := NULL;
    next_status := 'terminal_failure';
  END IF;
  UPDATE public.query_execution
     SET status = CASE WHEN p_result_kind = 'observation' THEN 'succeeded' ELSE next_status END,
         finished_at = clock_timestamp(),
         duration_ms = p_duration_ms,
         http_status = p_http_status,
         provider_exchange_id = exchange_uuid,
         error_code = CASE WHEN p_result_kind = 'failure' THEN btrim(p_error_code) ELSE NULL END,
         error_message_sanitized = CASE WHEN p_result_kind = 'failure'
           THEN 'A consulta não produziu uma observação válida.' ELSE NULL END
   WHERE id = execution_row.id;
  UPDATE public.query_job
     SET status = next_status,
         available_at = coalesce(retry_at, clock_timestamp()),
         lease_token = NULL,
         lease_expires_at = NULL,
         locked_by = NULL,
         finished_at = CASE WHEN next_status IN ('succeeded', 'terminal_failure')
                            THEN clock_timestamp() ELSE NULL END,
         last_error_code = CASE WHEN p_result_kind = 'failure' THEN btrim(p_error_code) ELSE NULL END,
         last_error_message = CASE WHEN p_result_kind = 'failure'
           THEN 'A consulta não produziu uma observação válida.' ELSE NULL END,
         updated_at = clock_timestamp()
   WHERE id = job_row.id;
  PERFORM public.phase9_write_system_audit(
    'query_execution.completed', 'query_execution', execution_row.id, job_row.office_id,
    jsonb_build_object(
      'result_kind', p_result_kind, 'status', p_result_status,
      'attempt_number', job_row.attempt_count,
      'http_status', p_http_status
    ),
    'system_worker', job_row.locked_by
  );
  IF next_status = 'retry_scheduled' THEN
    PERFORM public.phase9_write_system_audit(
      'query_job.retry_scheduled', 'query_job', job_row.id, job_row.office_id,
      jsonb_build_object(
        'status', next_status, 'error_code', p_error_code,
        'attempt_number', job_row.attempt_count, 'retry_after_ms', retry_delay_ms
      ),
      'system_worker', job_row.locked_by
    );
  ELSIF next_status = 'terminal_failure' THEN
    PERFORM public.phase9_write_system_audit(
      'query_job.terminal_failure', 'query_job', job_row.id, job_row.office_id,
      jsonb_build_object('status', next_status, 'error_code', p_error_code,
                         'attempt_number', job_row.attempt_count),
      'system_worker', job_row.locked_by
    );
  END IF;
  job_id := job_row.id;
  execution_id := execution_row.id;
  job_status := next_status;
  exchange_id := exchange_uuid;
  snapshot_id := snapshot_uuid;
  next_attempt_at := retry_at;
  RETURN NEXT;
END;
$$;

-- 4. RPC realignment1_request_process_refresh: on-demand manual refresh with transactional locking, deduplication and human audit
CREATE OR REPLACE FUNCTION public.realignment1_request_process_refresh(
  p_process_id UUID
)
RETURNS TABLE (
  job_id UUID,
  process_id UUID,
  office_id UUID,
  status TEXT,
  created_at TIMESTAMPTZ,
  is_reused BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  proc_row public.legal_process%ROWTYPE;
  active_job public.query_job%ROWTYPE;
  new_job_id UUID;
  v_idempotency_key TEXT;
  v_fingerprint TEXT;
  v_correlation TEXT;
  v_provider_id TEXT := 'datajud_public';
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_process_id IS NULL THEN
    RAISE EXCEPTION 'invalid manual refresh request' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('juridico.phase9_internal', '1', true);

  -- Lock process row to prevent concurrent race condition
  SELECT lp.* INTO proc_row
    FROM public.legal_process lp
   WHERE lp.id = p_process_id
     AND lp.office_id = actor.actor_office_id
   FOR UPDATE;

  IF proc_row.id IS NULL THEN
    RAISE EXCEPTION 'process not found in office' USING ERRCODE = '42501';
  END IF;

  IF proc_row.status <> 'active' OR proc_row.is_public IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'process is not eligible for manual refresh' USING ERRCODE = '42501';
  END IF;

  -- Check for existing active job
  SELECT * INTO active_job
    FROM public.query_job
   WHERE public.query_job.office_id = actor.actor_office_id
     AND public.query_job.process_id = proc_row.id
     AND public.query_job.provider_id = v_provider_id
     AND public.query_job.job_kind = 'manual_refresh'
     AND public.query_job.status IN ('pending', 'running', 'retry_scheduled')
   ORDER BY public.query_job.created_at DESC
   LIMIT 1;

  IF active_job.id IS NOT NULL THEN
    job_id := active_job.id;
    process_id := active_job.process_id;
    office_id := active_job.office_id;
    status := active_job.status;
    created_at := active_job.created_at;
    is_reused := true;
    RETURN NEXT;
    RETURN;
  END IF;

  v_idempotency_key := 'manual-refresh:' || proc_row.id::TEXT || ':' || gen_random_uuid()::TEXT;
  v_fingerprint := encode(extensions.digest(
    convert_to('manual-refresh:' || proc_row.id::TEXT || ':' || actor.actor_id::TEXT || ':' || clock_timestamp()::TEXT, 'UTF8'),
    'sha256'
  ), 'hex');
  v_correlation := 'job-manual-refresh:' || gen_random_uuid()::TEXT;

  INSERT INTO public.query_job (
    office_id, process_id, provider_id, capability, job_kind,
    scheduled_window_utc, idempotency_key, request_fingerprint,
    correlation_id, status, attempt_count, max_attempts, available_at,
    created_by
  ) VALUES (
    actor.actor_office_id, proc_row.id, v_provider_id, 'process_observation', 'manual_refresh',
    NULL, v_idempotency_key, v_fingerprint,
    v_correlation, 'pending', 0, 3, clock_timestamp(),
    actor.actor_id
  ) RETURNING id, public.query_job.created_at INTO new_job_id, created_at;

  PERFORM public.phase9_write_user_audit(
    'query_job.manual_refresh_requested',
    'query_job',
    new_job_id,
    jsonb_build_object(
      'process_id', proc_row.id,
      'provider_id', v_provider_id,
      'correlation_id', v_correlation,
      'job_id', new_job_id
    )
  );

  job_id := new_job_id;
  process_id := proc_row.id;
  office_id := actor.actor_office_id;
  status := 'pending';
  is_reused := false;
  RETURN NEXT;
END;
$$;

-- 7. RPC realignment1_claim_query_job: strictly targeted claim (backend-only)
CREATE OR REPLACE FUNCTION public.realignment1_claim_query_job(
  p_worker_id TEXT,
  p_target_job_id UUID,
  p_lease_duration_ms INTEGER DEFAULT 30000
)
RETURNS TABLE (
  job_id UUID,
  execution_id UUID,
  office_id UUID,
  process_id UUID,
  provider_id TEXT,
  capability TEXT,
  job_kind TEXT,
  subject_ref TEXT,
  request_fingerprint TEXT,
  correlation_id TEXT,
  attempt_number INTEGER,
  lease_token UUID,
  lease_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  job_row public.query_job%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  execution_row public.query_execution%ROWTYPE;
  execution_uuid UUID;
  token UUID;
  expires_at TIMESTAMPTZ;
  execution_correlation TEXT;
  next_status TEXT;
  next_at TIMESTAMPTZ;
BEGIN
  IF p_target_job_id IS NULL THEN
    RAISE EXCEPTION 'p_target_job_id is required for targeted claim' USING ERRCODE = '22023';
  END IF;
  IF p_worker_id IS NULL OR p_worker_id !~ '^[A-Za-z0-9._:-]{1,120}$'
     OR p_lease_duration_ms <= 15000 OR p_lease_duration_ms > 120000 THEN
    RAISE EXCEPTION 'invalid worker targeted claim input' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('juridico.phase9_internal', '1', true);

  SELECT * INTO job_row
    FROM public.query_job
   WHERE id = p_target_job_id
   FOR UPDATE;

  IF job_row.id IS NULL THEN
    RETURN;
  END IF;

  -- Ensure job matches the targeted criteria strictly
  IF job_row.job_kind <> 'manual_refresh'
     OR job_row.provider_id <> 'datajud_public'
     OR job_row.capability <> 'process_observation' THEN
    RETURN;
  END IF;

  -- If job is currently running but lease has expired, recover exclusively this targeted job
  IF job_row.status = 'running' AND job_row.lease_expires_at <= clock_timestamp() THEN
    SELECT * INTO execution_row
      FROM public.query_execution
     WHERE query_job_id = job_row.id
       AND public.query_execution.status = 'running'
     ORDER BY attempt_number DESC
     LIMIT 1
     FOR UPDATE;

    IF job_row.attempt_count < job_row.max_attempts THEN
      next_status := 'retry_scheduled';
      next_at := clock_timestamp() + (1000 * job_row.attempt_count * INTERVAL '1 millisecond');
    ELSE
      next_status := 'terminal_failure';
      next_at := clock_timestamp();
    END IF;

    IF execution_row.id IS NOT NULL THEN
      UPDATE public.query_execution
         SET status = 'terminal_failure',
             finished_at = clock_timestamp(),
             error_code = 'worker_lease_expired',
             error_message_sanitized = 'A tentativa expirou antes da conclusão.'
       WHERE id = execution_row.id;
    END IF;

    UPDATE public.query_job
       SET status = next_status,
           available_at = next_at,
           lease_token = NULL,
           lease_expires_at = NULL,
           locked_by = NULL,
           finished_at = CASE WHEN next_status = 'terminal_failure' THEN clock_timestamp() ELSE NULL END,
           last_error_code = 'worker_lease_expired',
           last_error_message = 'A tentativa expirou antes da conclusão.',
           updated_at = clock_timestamp()
     WHERE id = job_row.id
     RETURNING * INTO job_row;

    PERFORM public.phase9_write_system_audit(
      CASE WHEN next_status = 'retry_scheduled'
           THEN 'query_job.lease_recovered'
           ELSE 'query_job.terminal_failure' END,
      'query_job', job_row.id, job_row.office_id,
      jsonb_build_object('error_code', 'worker_lease_expired', 'attempt_number', job_row.attempt_count),
      'system_worker', p_worker_id
    );
  END IF;

  -- Now verify if the targeted job is claimable
  IF job_row.status NOT IN ('pending', 'retry_scheduled')
     OR job_row.available_at > clock_timestamp()
     OR job_row.attempt_count >= job_row.max_attempts THEN
    RETURN;
  END IF;

  SELECT lp.* INTO process_row
    FROM public.legal_process lp
   WHERE lp.id = job_row.process_id
     AND lp.office_id = job_row.office_id
   FOR SHARE;

  IF process_row.id IS NULL OR process_row.status <> 'active'
     OR process_row.is_public IS DISTINCT FROM true
     OR (job_row.job_kind = 'scheduled' AND process_row.monitoring_status <> 'active') THEN
    UPDATE public.query_job
       SET status = 'terminal_failure',
           last_error_code = 'process_not_eligible',
           last_error_message = 'Processo não elegível para observação.',
           finished_at = clock_timestamp(),
           updated_at = clock_timestamp(),
           available_at = clock_timestamp()
     WHERE id = job_row.id;
    PERFORM public.phase9_write_system_audit(
      'query_job.terminal_failure', 'query_job', job_row.id, job_row.office_id,
      jsonb_build_object('error_code', 'process_not_eligible', 'reason', 'pre_claim_guard'),
      'system_worker', p_worker_id
    );
    RETURN;
  END IF;

  token := gen_random_uuid();
  expires_at := clock_timestamp() + (p_lease_duration_ms * INTERVAL '1 millisecond');

  UPDATE public.query_job
     SET status = 'running',
         attempt_count = attempt_count + 1,
         lease_token = token,
         lease_expires_at = expires_at,
         locked_by = p_worker_id,
         updated_at = clock_timestamp()
   WHERE id = job_row.id
     AND status IN ('pending', 'retry_scheduled')
   RETURNING * INTO job_row;

  execution_correlation := job_row.correlation_id || ':attempt:' || job_row.attempt_count::TEXT;

  INSERT INTO public.query_execution (
    office_id, query_job_id, process_id, provider_id, capability,
    attempt_number, status, correlation_id
  ) VALUES (
    job_row.office_id, job_row.id, job_row.process_id, job_row.provider_id,
    job_row.capability, job_row.attempt_count, 'running', execution_correlation
  ) RETURNING id INTO execution_uuid;

  PERFORM public.phase9_write_system_audit(
    'query_job.claimed', 'query_job', job_row.id, job_row.office_id,
    jsonb_build_object('attempt_number', job_row.attempt_count),
    'system_worker', p_worker_id
  );
  PERFORM public.phase9_write_system_audit(
    'query_execution.started', 'query_execution', execution_uuid, job_row.office_id,
    jsonb_build_object('attempt_number', job_row.attempt_count),
    'system_worker', p_worker_id
  );

  job_id := job_row.id;
  execution_id := execution_uuid;
  office_id := job_row.office_id;
  process_id := job_row.process_id;
  provider_id := job_row.provider_id;
  capability := job_row.capability;
  job_kind := job_row.job_kind;
  subject_ref := process_row.cnj_number;
  request_fingerprint := job_row.request_fingerprint;
  correlation_id := execution_correlation;
  attempt_number := job_row.attempt_count;
  lease_token := token;
  lease_expires_at := expires_at;
  RETURN NEXT;
END;
$$;

-- 8. Permissions and Grants
REVOKE ALL ON FUNCTION public.realignment1_request_process_refresh(UUID) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.realignment1_request_process_refresh(UUID) TO authenticated;

-- Targeted claim is strictly backend-only (service_role only)
REVOKE ALL ON FUNCTION public.realignment1_claim_query_job(TEXT, UUID, INTEGER) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.realignment1_claim_query_job(TEXT, UUID, INTEGER) TO service_role;
