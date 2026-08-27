SET lock_timeout = '2s';

-- Fase 9: hardening incremental de stale lease.
-- A migration 00011 permanece imutável; esta migration reaplica somente a conclusão protegida.

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
     OR process_row.monitoring_status <> 'active'
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
         'worker_provider_execution_failed'
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
