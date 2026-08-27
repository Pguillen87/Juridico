SET lock_timeout = '2s';

-- Fase 11: central operacional de falhas e outbox interno/sintético.
-- Esta migration é aditiva e não altera migrations publicadas das Fases 9 e 10.

CREATE OR REPLACE FUNCTION public.phase11_failure_class(p_failure_code TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN p_failure_code IN (
      'timeout', 'datajud_timeout', 'datajud_dns_failure',
      'datajud_network_failure', 'datajud_rate_limited',
      'datajud_source_unavailable', 'provider_backend_unavailable'
    ) THEN 'provider_transient'
    WHEN p_failure_code IN ('manual_review_required', 'manual_evidence_missing')
      THEN 'provider_manual_review'
    WHEN p_failure_code IN (
      'not_found', 'datajud_not_found', 'not_supported',
      'capability_not_supported', 'operation_not_supported',
      'datajud_input_schema_invalid', 'datajud_schema_invalid',
      'datajud_process_mismatch', 'datajud_process_not_eligible',
      'provider_not_registered', 'manual_process_mismatch',
      'provider_backend_unauthorized'
    ) THEN 'provider_permanent'
    WHEN p_failure_code IN ('provider_persistence_failed') THEN 'persistence'
    WHEN p_failure_code IN ('comparison_persistence_failed') THEN 'comparison'
    WHEN p_failure_code IN ('scheduler_failure') THEN 'scheduler'
    WHEN p_failure_code IN ('worker_failure', 'worker_lease_expired',
                            'worker_provider_execution_failed') THEN 'worker'
    WHEN p_failure_code IN ('outbox_persistence_failed', 'audit_failure')
      THEN 'notification'
    ELSE 'provider_permanent'
  END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_hash_key(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
  SELECT encode(extensions.digest(convert_to(p_value, 'UTF8'), 'sha256'), 'hex');
$$;

CREATE TABLE public.failure_incident (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  process_id UUID,
  origin TEXT NOT NULL CHECK (origin IN (
    'provider', 'query_execution', 'comparison', 'scheduler',
    'worker', 'persistence', 'notification'
  )),
  provider_id TEXT,
  capability TEXT,
  failure_stage TEXT NOT NULL CHECK (failure_stage IN (
    'provider', 'persistence', 'comparison', 'scheduler', 'worker', 'notification'
  )),
  failure_class TEXT NOT NULL CHECK (failure_class IN (
    'provider_transient', 'provider_permanent', 'provider_manual_review',
    'persistence', 'comparison', 'scheduler', 'worker', 'notification'
  )),
  failure_code TEXT NOT NULL CHECK (failure_code IN (
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
  )),
  fingerprint TEXT NOT NULL CHECK (fingerprint ~ '^[0-9a-f]{64}$'),
  recovery_key TEXT NOT NULL CHECK (recovery_key ~ '^[0-9a-f]{64}$'),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  occurrence_count INTEGER NOT NULL DEFAULT 0 CHECK (occurrence_count >= 0),
  current_execution_id UUID,
  current_job_id UUID,
  assigned_to_user_id UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  resolution_kind TEXT,
  resolution_code TEXT,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  resolution_note_sanitized TEXT CHECK (
    resolution_note_sanitized IS NULL OR char_length(resolution_note_sanitized) BETWEEN 1 AND 2000
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, fingerprint),
  FOREIGN KEY (office_id, process_id)
    REFERENCES public.legal_process(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, current_execution_id)
    REFERENCES public.query_execution(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, current_job_id)
    REFERENCES public.query_job(office_id, id) ON DELETE RESTRICT,
  CHECK (process_id IS NOT NULL OR origin IN ('scheduler', 'worker', 'persistence', 'notification')),
  CHECK ((status = 'resolved' AND resolved_at IS NOT NULL)
      OR (status = 'open' AND resolved_at IS NULL)),
  CHECK ((status = 'resolved'
          AND ((resolution_kind = 'auto_recovered' AND resolved_by IS NULL)
            OR (resolution_kind = 'manual' AND resolved_by IS NOT NULL)))
      OR (status = 'open' AND resolved_by IS NULL))
);

CREATE INDEX failure_incident_status_idx
  ON public.failure_incident (office_id, status, last_seen_at DESC);
CREATE INDEX failure_incident_process_idx
  ON public.failure_incident (office_id, process_id, last_seen_at DESC);
CREATE INDEX failure_incident_origin_code_idx
  ON public.failure_incident (office_id, origin, failure_code, last_seen_at DESC);

CREATE TABLE public.failure_occurrence (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  incident_id UUID NOT NULL,
  event_kind TEXT NOT NULL CHECK (event_kind IN (
    'failure_observed', 'auto_resolved', 'manual_resolved', 'reopened',
    'manual_reprocess_requested', 'assignee_changed', 'operator_note_added'
  )),
  process_id UUID,
  origin TEXT NOT NULL CHECK (origin IN (
    'provider', 'query_execution', 'comparison', 'scheduler',
    'worker', 'persistence', 'notification'
  )),
  failure_stage TEXT CHECK (failure_stage IS NULL OR failure_stage IN (
    'provider', 'persistence', 'comparison', 'scheduler', 'worker', 'notification'
  )),
  failure_class TEXT CHECK (failure_class IS NULL OR failure_class IN (
    'provider_transient', 'provider_permanent', 'provider_manual_review',
    'persistence', 'comparison', 'scheduler', 'worker', 'notification'
  )),
  failure_code TEXT CHECK (failure_code IS NULL OR failure_code IN (
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
  )),
  source_type TEXT NOT NULL CHECK (source_type IN (
    'query_execution', 'query_job', 'provider_exchange', 'process_comparison',
    'detected_change', 'scheduler', 'worker', 'persistence', 'incident'
  )),
  source_id TEXT CHECK (source_id IS NULL OR source_id ~ '^[A-Za-z0-9._:-]{1,240}$'),
  recovery_key TEXT CHECK (recovery_key IS NULL OR recovery_key ~ '^[0-9a-f]{64}$'),
  event_actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  previous_assignee_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  new_assignee_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  operator_note_sanitized TEXT CHECK (
    operator_note_sanitized IS NULL OR char_length(operator_note_sanitized) BETWEEN 1 AND 2000
  ),
  resolution_note_sanitized TEXT CHECK (
    resolution_note_sanitized IS NULL OR char_length(resolution_note_sanitized) BETWEEN 1 AND 2000
  ),
  query_execution_id UUID,
  query_job_id UUID,
  provider_exchange_id UUID,
  process_comparison_id UUID,
  attempt_number INTEGER CHECK (attempt_number IS NULL OR attempt_number BETWEEN 1 AND 3),
  observed_job_status TEXT CHECK (observed_job_status IS NULL OR observed_job_status IN (
    'pending', 'running', 'retry_scheduled', 'succeeded', 'terminal_failure', 'cancelled'
  )),
  sanitized_message_code TEXT CHECK (
    sanitized_message_code IS NULL OR char_length(sanitized_message_code) BETWEEN 1 AND 120
  ),
  context_allowlisted JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(context_allowlisted) = 'object'),
  occurrence_idempotency_key TEXT NOT NULL
    CHECK (char_length(btrim(occurrence_idempotency_key)) BETWEEN 1 AND 240),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, occurrence_idempotency_key),
  FOREIGN KEY (office_id, incident_id)
    REFERENCES public.failure_incident(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, process_id)
    REFERENCES public.legal_process(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, query_execution_id)
    REFERENCES public.query_execution(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, query_job_id)
    REFERENCES public.query_job(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, provider_exchange_id)
    REFERENCES public.provider_exchange(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, process_comparison_id)
    REFERENCES public.process_comparison(office_id, id) ON DELETE RESTRICT,
  CHECK ((event_kind = 'failure_observed' AND failure_code IS NOT NULL)
      OR (event_kind <> 'failure_observed')),
  CHECK ((event_kind = 'assignee_changed'
          AND (previous_assignee_user_id IS DISTINCT FROM new_assignee_user_id))
      OR event_kind <> 'assignee_changed'),
  CHECK ((event_kind = 'operator_note_added' AND operator_note_sanitized IS NOT NULL)
      OR event_kind <> 'operator_note_added'),
  CHECK ((event_kind = 'manual_resolved' AND resolution_note_sanitized IS NOT NULL)
      OR event_kind <> 'manual_resolved')
);

CREATE INDEX failure_occurrence_incident_idx
  ON public.failure_occurrence (office_id, incident_id, occurred_at DESC);
CREATE INDEX failure_occurrence_attempt_idx
  ON public.failure_occurrence (office_id, attempt_number, occurred_at DESC)
  WHERE attempt_number IS NOT NULL;
CREATE INDEX failure_occurrence_source_idx
  ON public.failure_occurrence (office_id, source_type, source_id, occurred_at DESC);

CREATE TABLE public.notification_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  event_kind TEXT NOT NULL CHECK (event_kind IN (
    'failure_observed', 'incident_auto_resolved', 'incident_reopened', 'detected_change'
  )),
  incident_id UUID,
  occurrence_id UUID,
  detected_change_id UUID,
  channel TEXT NOT NULL CHECK (channel IN ('in_app', 'mock_email')),
  recipient_scope TEXT NOT NULL CHECK (recipient_scope IN ('office_failure_operators')),
  template_version TEXT NOT NULL CHECK (template_version IN ('failure.v1', 'change.v1')),
  payload_sanitized JSONB NOT NULL CHECK (
    jsonb_typeof(payload_sanitized) = 'object'
    AND NOT public.provider_payload_has_sensitive_key(payload_sanitized)
  ),
  idempotency_key TEXT NOT NULL
    CHECK (char_length(btrim(idempotency_key)) BETWEEN 1 AND 240),
  simulation_only BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  emitted_at TIMESTAMPTZ,
  UNIQUE (office_id, id),
  UNIQUE (office_id, idempotency_key),
  FOREIGN KEY (office_id, incident_id)
    REFERENCES public.failure_incident(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, occurrence_id)
    REFERENCES public.failure_occurrence(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, detected_change_id)
    REFERENCES public.detected_change(office_id, id) ON DELETE RESTRICT,
  CHECK (simulation_only = true),
  CHECK (
    (event_kind = 'detected_change'
      AND detected_change_id IS NOT NULL
      AND incident_id IS NULL
      AND occurrence_id IS NULL
      AND template_version = 'change.v1')
    OR (event_kind <> 'detected_change'
      AND detected_change_id IS NULL
      AND incident_id IS NOT NULL
      AND occurrence_id IS NOT NULL
      AND template_version = 'failure.v1')
  ),
  CHECK (channel = 'mock_email' OR channel = 'in_app')
);

CREATE INDEX notification_outbox_created_idx
  ON public.notification_outbox (office_id, created_at DESC);
CREATE INDEX notification_outbox_incident_idx
  ON public.notification_outbox (office_id, incident_id, created_at DESC)
  WHERE incident_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.phase11_block_incident_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase11_internal', true) <> '1' THEN
    RAISE EXCEPTION 'failure_incident is writable only through phase 11 domain functions'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'failure_incident has no physical deletion'
      USING ERRCODE = '42501';
  END IF;
  IF OLD.id IS DISTINCT FROM NEW.id
     OR OLD.office_id IS DISTINCT FROM NEW.office_id
     OR OLD.process_id IS DISTINCT FROM NEW.process_id
     OR OLD.origin IS DISTINCT FROM NEW.origin
     OR OLD.provider_id IS DISTINCT FROM NEW.provider_id
     OR OLD.capability IS DISTINCT FROM NEW.capability
     OR OLD.failure_stage IS DISTINCT FROM NEW.failure_stage
     OR OLD.failure_class IS DISTINCT FROM NEW.failure_class
     OR OLD.failure_code IS DISTINCT FROM NEW.failure_code
     OR OLD.fingerprint IS DISTINCT FROM NEW.fingerprint
     OR OLD.recovery_key IS DISTINCT FROM NEW.recovery_key
     OR OLD.first_seen_at IS DISTINCT FROM NEW.first_seen_at
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
  THEN
    RAISE EXCEPTION 'failure_incident identity is immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_block_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase11_internal', true) <> '1' THEN
    RAISE EXCEPTION '% is append-only and writable only by internal phase 11 functions'
      USING ERRCODE = '42501', HINT = 'Use the authorized domain command.';
  END IF;
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION '% is append-only and has no physical mutation' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER phase11_incident_guard
BEFORE UPDATE OR DELETE ON public.failure_incident
FOR EACH ROW EXECUTE FUNCTION public.phase11_block_incident_mutation();

CREATE TRIGGER phase11_occurrence_guard
BEFORE UPDATE OR DELETE ON public.failure_occurrence
FOR EACH ROW EXECUTE FUNCTION public.phase11_block_append_only_mutation();

CREATE TRIGGER phase11_outbox_guard
BEFORE UPDATE OR DELETE ON public.notification_outbox
FOR EACH ROW EXECUTE FUNCTION public.phase11_block_append_only_mutation();

ALTER TABLE public.failure_incident ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.failure_occurrence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.failure_incident, public.failure_occurrence,
  public.notification_outbox FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.failure_incident, public.failure_occurrence TO authenticated;

CREATE POLICY failure_incident_select_same_office
ON public.failure_incident
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

CREATE POLICY failure_occurrence_select_same_office
ON public.failure_occurrence
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

CREATE OR REPLACE FUNCTION public.phase11_write_operational_audit(
  p_action TEXT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_office_id UUID,
  p_actor_user_id UUID,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  audit_id BIGINT;
  metadata_key TEXT;
  actor_row RECORD;
BEGIN
  IF p_action NOT IN (
    'failure.incident.created', 'failure.incident.observed',
    'failure.incident.reopened', 'failure.incident.auto_resolved',
    'failure.incident.manual_resolved', 'failure.incident.assignee_changed',
    'failure.incident.note_added', 'failure.incident.manual_reprocess_requested',
    'failure.technical.recorded', 'notification.outbox.created'
  ) OR p_entity_type NOT IN (
    'failure_incident', 'failure_occurrence', 'notification_outbox',
    'query_execution', 'query_job', 'detected_change'
  ) THEN
    RAISE EXCEPTION 'phase 11 audit event is not allowlisted' USING ERRCODE = '22023';
  END IF;
  IF p_office_id IS NULL OR p_entity_id IS NULL
     OR p_metadata IS NULL OR jsonb_typeof(p_metadata) <> 'object' THEN
    RAISE EXCEPTION 'invalid phase 11 audit input' USING ERRCODE = '22023';
  END IF;
  IF p_actor_user_id IS NOT NULL THEN
    SELECT up.id, up.office_id, up.role, up.is_active, o.is_active AS office_active
      INTO actor_row
      FROM public.user_profile up
      JOIN public.office o ON o.id = up.office_id
     WHERE up.id = p_actor_user_id;
    IF actor_row.id IS NULL OR actor_row.office_id IS DISTINCT FROM p_office_id
       OR actor_row.is_active IS DISTINCT FROM true
       OR actor_row.office_active IS DISTINCT FROM true
       OR actor_row.role NOT IN ('lawyer', 'operator') THEN
      RAISE EXCEPTION 'invalid phase 11 audit actor' USING ERRCODE = '42501';
    END IF;
  END IF;
  FOR metadata_key IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF metadata_key NOT IN (
      'before_status', 'after_status', 'failure_code', 'failure_class',
      'failure_stage', 'origin', 'fingerprint', 'recovery_key', 'attempt_number',
      'source_type', 'source_id', 'channel', 'recipient_scope',
      'template_version', 'detected_change_id', 'occurrence_id', 'idempotency_key',
      'job_id', 'execution_id', 'assignee_before', 'assignee_after',
      'resolution_code', 'note_length', 'process_id'
    ) THEN
      RAISE EXCEPTION 'phase 11 audit metadata key is not allowlisted'
        USING ERRCODE = '22023';
    END IF;
  END LOOP;
  INSERT INTO public.audit_log (
    audit_scope, office_id, actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    'operational', p_office_id, p_actor_user_id, p_action, p_entity_type,
    p_entity_id, p_metadata
  ) RETURNING id INTO audit_id;
  RETURN audit_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_enqueue_notification_internal(
  p_office_id UUID,
  p_event_kind TEXT,
  p_incident_id UUID,
  p_occurrence_id UUID,
  p_detected_change_id UUID,
  p_payload JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  channel_name TEXT;
  key_name TEXT;
  outbox_id UUID;
  base_key TEXT;
  template TEXT;
BEGIN
  IF current_setting('juridico.phase11_internal', true) <> '1' THEN
    RAISE EXCEPTION 'phase 11 outbox is backend-only' USING ERRCODE = '42501';
  END IF;
  IF p_event_kind NOT IN ('failure_observed', 'incident_auto_resolved',
                          'incident_reopened', 'detected_change')
     OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'invalid phase 11 notification input' USING ERRCODE = '22023';
  END IF;
  IF (p_event_kind = 'detected_change') <> (p_detected_change_id IS NOT NULL) THEN
    RAISE EXCEPTION 'detected change source mismatch' USING ERRCODE = '22023';
  END IF;
  IF p_event_kind <> 'detected_change'
     AND (p_incident_id IS NULL OR p_occurrence_id IS NULL) THEN
    RAISE EXCEPTION 'failure notification source is required' USING ERRCODE = '22023';
  END IF;
  FOR key_name IN SELECT jsonb_object_keys(p_payload) LOOP
    IF key_name NOT IN (
      'template_version', 'event_type', 'code', 'operational_priority',
      'incident_id', 'occurrence_id', 'detected_change_id', 'attempt_number',
      'process_id', 'message_code'
    ) THEN
      RAISE EXCEPTION 'phase 11 notification payload key is not allowlisted'
        USING ERRCODE = '22023';
    END IF;
  END LOOP;
  IF public.provider_payload_has_sensitive_key(p_payload) THEN
    RAISE EXCEPTION 'phase 11 notification payload contains a sensitive key'
      USING ERRCODE = '22023';
  END IF;
  template := CASE WHEN p_event_kind = 'detected_change' THEN 'change.v1' ELSE 'failure.v1' END;
  base_key := CASE
    WHEN p_event_kind = 'detected_change'
      THEN 'detected-change:' || p_detected_change_id::TEXT
    ELSE p_event_kind || ':' || p_occurrence_id::TEXT
  END;
  FOREACH channel_name IN ARRAY ARRAY['in_app', 'mock_email'] LOOP
    INSERT INTO public.notification_outbox (
      office_id, event_kind, incident_id, occurrence_id, detected_change_id,
      channel, recipient_scope, template_version, payload_sanitized,
      idempotency_key, simulation_only
    ) VALUES (
      p_office_id, p_event_kind, p_incident_id, p_occurrence_id,
      p_detected_change_id, channel_name, 'office_failure_operators', template,
      p_payload, base_key || ':' || channel_name, true
    )
    ON CONFLICT (office_id, idempotency_key) DO NOTHING
    RETURNING id INTO outbox_id;
    IF outbox_id IS NOT NULL THEN
      PERFORM public.phase11_write_operational_audit(
        'notification.outbox.created', 'notification_outbox', outbox_id,
        p_office_id, NULL,
        jsonb_build_object(
          'channel', channel_name,
          'recipient_scope', 'office_failure_operators',
          'template_version', template,
          'occurrence_id', p_occurrence_id,
          'detected_change_id', p_detected_change_id,
          'idempotency_key', base_key || ':' || channel_name
        )
      );
    END IF;
    outbox_id := NULL;
  END LOOP;
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
  IF current_setting('juridico.phase11_internal', true) <> '1' THEN
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

CREATE OR REPLACE FUNCTION public.phase11_record_execution_failure_internal(
  p_execution_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  e RECORD;
  class_value TEXT;
  context_value JSONB;
BEGIN
  IF p_execution_id IS NULL THEN
    RAISE EXCEPTION 'execution id is required' USING ERRCODE = '22023';
  END IF;
  SELECT e.id, e.office_id, e.process_id, e.provider_id, e.capability,
         e.attempt_number, e.status, e.error_code, e.http_status,
         e.provider_exchange_id, e.query_job_id, j.status AS job_status
    INTO e
    FROM public.query_execution e
    JOIN public.query_job j ON j.office_id = e.office_id AND j.id = e.query_job_id
   WHERE e.id = p_execution_id;
  IF e.id IS NULL THEN
    RAISE EXCEPTION 'query execution not found' USING ERRCODE = '42501';
  END IF;
  IF e.error_code IS NULL OR e.status NOT IN ('retry_scheduled', 'terminal_failure', 'cancelled') THEN
    RETURN NULL;
  END IF;
  class_value := public.phase11_failure_class(e.error_code);
  context_value := jsonb_build_object(
    'source', 'datajud', 'capability', e.capability, 'failure_stage', 'provider',
    'http_status', e.http_status
  );
  PERFORM set_config('juridico.phase11_internal', '1', true);
  RETURN public.phase11_record_failure_event_internal(
    e.office_id, e.process_id, 'provider', e.provider_id, e.capability, 'provider',
    class_value, e.error_code, context_value, e.id, e.query_job_id,
    e.provider_exchange_id, e.attempt_number, 'query_execution', e.id::TEXT
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_record_technical_failure_internal(
  p_office_id UUID,
  p_origin TEXT,
  p_failure_code TEXT,
  p_failure_stage TEXT,
  p_context_allowlisted JSONB,
  p_source_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  class_value TEXT;
BEGIN
  IF p_office_id IS NULL OR p_origin NOT IN (
       'comparison', 'scheduler', 'worker', 'persistence', 'notification'
     ) THEN
    RAISE EXCEPTION 'invalid technical failure scope' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.office WHERE id = p_office_id AND is_active = true) THEN
    RAISE EXCEPTION 'office is not active' USING ERRCODE = '42501';
  END IF;
  class_value := public.phase11_failure_class(p_failure_code);
  PERFORM set_config('juridico.phase11_internal', '1', true);
  RETURN public.phase11_record_failure_event_internal(
    p_office_id, NULL, p_origin, NULL, NULL, p_failure_stage, class_value,
    p_failure_code, p_context_allowlisted, NULL, NULL, NULL, NULL,
    CASE p_origin WHEN 'scheduler' THEN 'scheduler'
                 WHEN 'worker' THEN 'worker'
                 WHEN 'comparison' THEN 'process_comparison'
                 ELSE 'persistence' END,
    p_source_id
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
  e RECORD;
  incident_row RECORD;
  occurrence_id UUID;
  recovery_value TEXT;
  resolved_count INTEGER := 0;
BEGIN
  IF p_execution_id IS NULL THEN
    RAISE EXCEPTION 'execution id is required' USING ERRCODE = '22023';
  END IF;
  SELECT e.id, e.office_id, e.process_id, e.provider_id, e.capability,
         e.attempt_number, e.status, e.query_job_id
    INTO e
    FROM public.query_execution e
   WHERE e.id = p_execution_id;
  IF e.id IS NULL OR e.status <> 'succeeded'
     OR NOT EXISTS (SELECT 1 FROM public.process_snapshot ps
                     WHERE ps.office_id = e.office_id
                       AND ps.query_execution_id = e.id) THEN
    RETURN 0;
  END IF;
  recovery_value := public.phase11_hash_key(
    'recovery-v1|' || e.office_id::TEXT || '|' || e.process_id::TEXT || '|' ||
    e.provider_id || '|' || e.capability || '|provider|process'
  );
  PERFORM set_config('juridico.phase11_internal', '1', true);
  FOR incident_row IN
    SELECT fi.*
      FROM public.failure_incident fi
     WHERE fi.office_id = e.office_id
       AND fi.process_id = e.process_id
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
      e.office_id, incident_row.id, 'auto_resolved', e.process_id, 'provider',
      'provider', incident_row.failure_class, 'query_execution', e.id::TEXT,
      recovery_value, e.id, e.query_job_id, e.attempt_number, 'succeeded',
      'successful_observation', jsonb_build_object('source', 'datajud', 'capability', e.capability),
      'auto-resolved:' || incident_row.id::TEXT || ':' || e.id::TEXT
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
     WHERE office_id = e.office_id AND id = incident_row.id;
    PERFORM public.phase11_write_operational_audit(
      'failure.incident.auto_resolved', 'failure_occurrence', occurrence_id,
      e.office_id, NULL,
      jsonb_build_object('after_status', 'resolved', 'resolution_code', 'successful_observation',
                         'recovery_key', recovery_value, 'execution_id', e.id,
                         'attempt_number', e.attempt_number)
    );
    PERFORM public.phase11_enqueue_notification_internal(
      e.office_id, 'incident_auto_resolved', incident_row.id, occurrence_id, NULL,
      jsonb_build_object('template_version', 'failure.v1', 'event_type', 'incident_auto_resolved',
                         'code', 'successful_observation', 'operational_priority', 'low',
                         'incident_id', incident_row.id, 'occurrence_id', occurrence_id,
                         'attempt_number', e.attempt_number, 'process_id', e.process_id)
    );
    resolved_count := resolved_count + 1;
  END LOOP;
  RETURN resolved_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_emit_detected_change_internal(
  p_detected_change_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  change_row RECORD;
BEGIN
  IF p_detected_change_id IS NULL THEN
    RAISE EXCEPTION 'detected change id is required' USING ERRCODE = '22023';
  END IF;
  SELECT dc.id, dc.office_id, dc.process_id, dc.comparison_id, pc.result
    INTO change_row
    FROM public.detected_change dc
    JOIN public.process_comparison pc
      ON pc.office_id = dc.office_id
     AND pc.id = dc.comparison_id
     AND pc.process_id = dc.process_id
   WHERE dc.id = p_detected_change_id;
  IF change_row.id IS NULL OR change_row.result <> 'changed' THEN
    RAISE EXCEPTION 'only a valid changed comparison may emit a notification'
      USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('juridico.phase11_internal', '1', true);
  PERFORM public.phase11_enqueue_notification_internal(
    change_row.office_id, 'detected_change', NULL, NULL, change_row.id,
    jsonb_build_object('template_version', 'change.v1', 'event_type', 'detected_change',
                       'code', 'snapshot_changed', 'operational_priority', 'high',
                       'detected_change_id', change_row.id, 'process_id', change_row.process_id)
  );
  RETURN change_row.id;
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

CREATE OR REPLACE FUNCTION public.phase11_resolve_failure_incident(
  p_incident_id UUID,
  p_resolution_code TEXT,
  p_resolution_note TEXT,
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
  occurrence_id UUID;
  note_value TEXT;
  event_key TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_incident_id IS NULL OR p_resolution_code NOT IN (
       'closed_by_operator', 'not_reproducible', 'manual_review_complete', 'reprocessed'
     ) OR p_idempotency_key IS NULL
     OR btrim(p_idempotency_key) !~ '^[A-Za-z0-9._:-]{1,120}$' THEN
    RAISE EXCEPTION 'invalid failure resolution input' USING ERRCODE = '22023';
  END IF;
  note_value := NULLIF(regexp_replace(btrim(coalesce(p_resolution_note, '')), '[[:space:]]+', ' ', 'g'), '');
  IF note_value IS NULL OR char_length(note_value) > 2000
     OR note_value ~ '[<>]'
     OR note_value ~* '(token|secret|senha|authorization|raw[ _-]?payload|stack[ _-]?trace|credencial)' THEN
    RAISE EXCEPTION 'resolution note is not allowed' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO incident_row
    FROM public.failure_incident
   WHERE id = p_incident_id AND office_id = actor.actor_office_id
   FOR UPDATE;
  IF incident_row.id IS NULL THEN
    RAISE EXCEPTION 'failure incident not found' USING ERRCODE = '42501';
  END IF;
  IF incident_row.status = 'resolved' THEN
    RETURN incident_row.id;
  END IF;
  event_key := 'manual-resolved:' || actor.actor_office_id::TEXT || ':' || btrim(p_idempotency_key);
  PERFORM set_config('juridico.phase11_internal', '1', true);
  INSERT INTO public.failure_occurrence (
    office_id, incident_id, event_kind, process_id, origin, failure_stage,
    failure_class, failure_code, source_type, source_id, recovery_key,
    query_execution_id, query_job_id, attempt_number, resolution_note_sanitized,
    sanitized_message_code, context_allowlisted, occurrence_idempotency_key,
    event_actor_user_id
  ) VALUES (
    actor.actor_office_id, incident_row.id, 'manual_resolved', incident_row.process_id,
    incident_row.origin, incident_row.failure_stage, incident_row.failure_class,
    incident_row.failure_code, 'incident', incident_row.id::TEXT, incident_row.recovery_key,
    incident_row.current_execution_id, incident_row.current_job_id, NULL, note_value,
    p_resolution_code, jsonb_build_object('operation', 'manual_resolution'), event_key,
    actor.actor_id
  ) ON CONFLICT (office_id, occurrence_idempotency_key) DO NOTHING
  RETURNING id INTO occurrence_id;
  IF occurrence_id IS NULL THEN
    RETURN incident_row.id;
  END IF;
  UPDATE public.failure_incident
     SET status = 'resolved', resolution_kind = 'manual',
         resolution_code = p_resolution_code, resolved_at = clock_timestamp(),
         resolved_by = actor.actor_id, resolution_note_sanitized = note_value,
         updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = incident_row.id;
  PERFORM public.phase11_write_operational_audit(
    'failure.incident.manual_resolved', 'failure_occurrence', occurrence_id,
    actor.actor_office_id, actor.actor_id,
    jsonb_build_object('after_status', 'resolved', 'resolution_code', p_resolution_code,
                       'note_length', char_length(note_value), 'idempotency_key', btrim(p_idempotency_key))
  );
  RETURN incident_row.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_assign_failure_incident(
  p_incident_id UUID,
  p_assignee_user_id UUID,
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
  assignee_row RECORD;
  occurrence_id UUID;
  event_key TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_incident_id IS NULL OR p_idempotency_key IS NULL
     OR btrim(p_idempotency_key) !~ '^[A-Za-z0-9._:-]{1,120}$' THEN
    RAISE EXCEPTION 'invalid failure assignment input' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO incident_row
    FROM public.failure_incident
   WHERE id = p_incident_id AND office_id = actor.actor_office_id
   FOR UPDATE;
  IF incident_row.id IS NULL THEN
    RAISE EXCEPTION 'failure incident not found' USING ERRCODE = '42501';
  END IF;
  IF p_assignee_user_id IS NOT NULL THEN
    SELECT up.id, up.office_id, up.role, up.is_active, o.is_active AS office_active
      INTO assignee_row
      FROM public.user_profile up
      JOIN public.office o ON o.id = up.office_id
     WHERE up.id = p_assignee_user_id;
    IF assignee_row.id IS NULL OR assignee_row.office_id IS DISTINCT FROM actor.actor_office_id
       OR assignee_row.is_active IS DISTINCT FROM true
       OR assignee_row.office_active IS DISTINCT FROM true
       OR assignee_row.role NOT IN ('lawyer', 'operator') THEN
      RAISE EXCEPTION 'assignee is not an active operational user in actor office'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  IF incident_row.assigned_to_user_id IS NOT DISTINCT FROM p_assignee_user_id THEN
    RETURN incident_row.id;
  END IF;
  event_key := 'assignee-changed:' || actor.actor_office_id::TEXT || ':' || btrim(p_idempotency_key);
  PERFORM set_config('juridico.phase11_internal', '1', true);
  INSERT INTO public.failure_occurrence (
    office_id, incident_id, event_kind, process_id, origin, failure_stage,
    failure_class, failure_code, source_type, source_id, recovery_key,
    previous_assignee_user_id, new_assignee_user_id, context_allowlisted,
    occurrence_idempotency_key, event_actor_user_id
  ) VALUES (
    actor.actor_office_id, incident_row.id, 'assignee_changed', incident_row.process_id,
    incident_row.origin, incident_row.failure_stage, incident_row.failure_class,
    incident_row.failure_code, 'incident', incident_row.id::TEXT, incident_row.recovery_key,
    incident_row.assigned_to_user_id, p_assignee_user_id,
    jsonb_build_object('operation', 'assignment'), event_key, actor.actor_id
  ) ON CONFLICT (office_id, occurrence_idempotency_key) DO NOTHING
  RETURNING id INTO occurrence_id;
  IF occurrence_id IS NULL THEN
    RETURN incident_row.id;
  END IF;
  UPDATE public.failure_incident
     SET assigned_to_user_id = p_assignee_user_id, updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = incident_row.id;
  PERFORM public.phase11_write_operational_audit(
    'failure.incident.assignee_changed', 'failure_occurrence', occurrence_id,
    actor.actor_office_id, actor.actor_id,
    jsonb_build_object('assignee_before', incident_row.assigned_to_user_id,
                       'assignee_after', p_assignee_user_id,
                       'idempotency_key', btrim(p_idempotency_key))
  );
  RETURN incident_row.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_add_failure_note(
  p_incident_id UUID,
  p_note TEXT,
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
  note_value TEXT;
  occurrence_id UUID;
  event_key TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_incident_id IS NULL OR p_note IS NULL OR p_idempotency_key IS NULL
     OR btrim(p_idempotency_key) !~ '^[A-Za-z0-9._:-]{1,120}$' THEN
    RAISE EXCEPTION 'invalid failure note input' USING ERRCODE = '22023';
  END IF;
  note_value := NULLIF(regexp_replace(btrim(p_note), '[[:space:]]+', ' ', 'g'), '');
  IF note_value IS NULL OR char_length(note_value) > 2000
     OR note_value ~ '[<>]'
     OR note_value ~* '(token|secret|senha|authorization|raw[ _-]?payload|stack[ _-]?trace|credencial)' THEN
    RAISE EXCEPTION 'failure note is not allowed' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO incident_row
    FROM public.failure_incident
   WHERE id = p_incident_id AND office_id = actor.actor_office_id
   FOR SHARE;
  IF incident_row.id IS NULL THEN
    RAISE EXCEPTION 'failure incident not found' USING ERRCODE = '42501';
  END IF;
  event_key := 'operator-note:' || actor.actor_office_id::TEXT || ':' || btrim(p_idempotency_key);
  PERFORM set_config('juridico.phase11_internal', '1', true);
  INSERT INTO public.failure_occurrence (
    office_id, incident_id, event_kind, process_id, origin, failure_stage,
    failure_class, failure_code, source_type, source_id, recovery_key,
    operator_note_sanitized, context_allowlisted, occurrence_idempotency_key,
    event_actor_user_id
  ) VALUES (
    actor.actor_office_id, incident_row.id, 'operator_note_added', incident_row.process_id,
    incident_row.origin, incident_row.failure_stage, incident_row.failure_class,
    incident_row.failure_code, 'incident', incident_row.id::TEXT, incident_row.recovery_key,
    note_value, jsonb_build_object('operation', 'operator_note'), event_key, actor.actor_id
  ) ON CONFLICT (office_id, occurrence_idempotency_key) DO NOTHING
  RETURNING id INTO occurrence_id;
  IF occurrence_id IS NULL THEN
    RETURN incident_row.id;
  END IF;
  UPDATE public.failure_incident SET updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = incident_row.id;
  PERFORM public.phase11_write_operational_audit(
    'failure.incident.note_added', 'failure_occurrence', occurrence_id,
    actor.actor_office_id, actor.actor_id,
    jsonb_build_object('note_length', char_length(note_value),
                       'idempotency_key', btrim(p_idempotency_key))
  );
  RETURN incident_row.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_list_failure_assignees()
RETURNS TABLE (id UUID, name TEXT, role TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator', 'reviewer') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT up.id, up.name, up.role::TEXT
    FROM public.user_profile up
   WHERE up.office_id = actor.actor_office_id
     AND up.is_active = true
     AND up.role IN ('lawyer', 'operator')
   ORDER BY up.name, up.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase11_list_failure_incidents(
  p_failure_type TEXT DEFAULT NULL,
  p_process_id UUID DEFAULT NULL,
  p_from_date DATE DEFAULT NULL,
  p_to_date DATE DEFAULT NULL,
  p_priority TEXT DEFAULT NULL,
  p_attempt_number INTEGER DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  incident_id UUID,
  office_id UUID,
  process_id UUID,
  origin TEXT,
  provider_id TEXT,
  capability TEXT,
  failure_stage TEXT,
  failure_class TEXT,
  failure_code TEXT,
  status TEXT,
  first_seen_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ,
  occurrence_count INTEGER,
  assigned_to_user_id UUID,
  operational_priority TEXT,
  next_action_code TEXT,
  next_attempt_at TIMESTAMPTZ,
  current_attempt_number INTEGER,
  last_attempt_number INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100
     OR p_attempt_number IS NOT NULL AND p_attempt_number NOT BETWEEN 1 AND 3
     OR p_priority IS NOT NULL AND p_priority NOT IN ('low', 'medium', 'high')
     OR p_status IS NOT NULL AND p_status NOT IN ('open', 'resolved')
     OR p_from_date IS NOT NULL AND p_to_date IS NOT NULL AND p_from_date > p_to_date THEN
    RAISE EXCEPTION 'invalid failure list filter' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY
  WITH base AS (
    SELECT fi.id AS incident_id, fi.office_id, fi.process_id, fi.origin,
           fi.provider_id, fi.capability, fi.failure_stage, fi.failure_class,
           fi.failure_code, fi.status, fi.first_seen_at, fi.last_seen_at,
           fi.occurrence_count, fi.assigned_to_user_id,
           CASE WHEN fi.status = 'resolved' THEN 'low'
                WHEN qj.status = 'retry_scheduled' THEN 'medium'
                ELSE 'high' END AS priority_value,
           CASE WHEN fi.status = 'resolved' THEN 'resolved'
                WHEN qj.status = 'retry_scheduled' THEN 'await_retry'
                WHEN qj.status = 'terminal_failure' THEN 'reprocess'
                ELSE 'review_manually' END AS action_value,
           CASE WHEN qj.status = 'retry_scheduled' THEN qj.available_at ELSE NULL END AS next_at,
           attempt.current_attempt_number, attempt.last_attempt_number
      FROM public.failure_incident fi
      LEFT JOIN public.query_job qj
        ON qj.office_id = fi.office_id AND qj.id = fi.current_job_id
      LEFT JOIN LATERAL (
        SELECT max(fo.attempt_number) FILTER (WHERE fo.event_kind = 'failure_observed')
                   AS current_attempt_number,
               max(fo.attempt_number) AS last_attempt_number
          FROM public.failure_occurrence fo
         WHERE fo.office_id = fi.office_id AND fo.incident_id = fi.id
      ) attempt ON true
     WHERE (p_failure_type IS NULL OR fi.failure_class = p_failure_type)
       AND (p_process_id IS NULL OR fi.process_id = p_process_id)
       AND (p_from_date IS NULL OR fi.last_seen_at >= p_from_date::TIMESTAMPTZ)
       AND (p_to_date IS NULL OR fi.last_seen_at < (p_to_date + 1)::TIMESTAMPTZ)
       AND (p_status IS NULL OR fi.status = p_status)
       AND (p_attempt_number IS NULL OR EXISTS (
         SELECT 1 FROM public.failure_occurrence fo_filter
          WHERE fo_filter.office_id = fi.office_id
            AND fo_filter.incident_id = fi.id
            AND fo_filter.attempt_number = p_attempt_number
       ))
  )
  SELECT b.incident_id, b.office_id, b.process_id, b.origin, b.provider_id,
         b.capability, b.failure_stage, b.failure_class, b.failure_code, b.status,
         b.first_seen_at, b.last_seen_at, b.occurrence_count, b.assigned_to_user_id,
         b.priority_value, b.action_value, b.next_at,
         b.current_attempt_number, b.last_attempt_number
    FROM base b
   WHERE p_priority IS NULL OR b.priority_value = p_priority
   ORDER BY b.last_seen_at DESC, b.incident_id DESC
   LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.phase11_failure_class(TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase11_hash_key(TEXT) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase11_block_incident_mutation() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase11_block_append_only_mutation() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase11_write_operational_audit(TEXT, TEXT, UUID, UUID, UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase11_enqueue_notification_internal(UUID, TEXT, UUID, UUID, UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase11_record_failure_event_internal(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, UUID, UUID, UUID, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase11_record_execution_failure_internal(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase11_record_technical_failure_internal(UUID, TEXT, TEXT, TEXT, JSONB, TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase11_reconcile_success_internal(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase11_emit_detected_change_internal(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase11_request_failure_reprocess(UUID, TEXT)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.phase11_resolve_failure_incident(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.phase11_assign_failure_incident(UUID, UUID, TEXT)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.phase11_add_failure_note(UUID, TEXT, TEXT)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.phase11_list_failure_assignees()
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.phase11_list_failure_incidents(TEXT, UUID, DATE, DATE, TEXT, INTEGER, TEXT, INTEGER)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.phase11_record_execution_failure_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.phase11_record_technical_failure_internal(UUID, TEXT, TEXT, TEXT, JSONB, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.phase11_reconcile_success_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.phase11_emit_detected_change_internal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.phase11_request_failure_reprocess(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase11_resolve_failure_incident(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase11_assign_failure_incident(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase11_add_failure_note(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase11_list_failure_assignees() TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase11_list_failure_incidents(TEXT, UUID, DATE, DATE, TEXT, INTEGER, TEXT, INTEGER) TO authenticated;

COMMENT ON TABLE public.failure_incident IS
  'Fase 11: agregado operacional por fingerprint; mutável somente por RPCs internas e sem exclusão física.';
COMMENT ON TABLE public.failure_occurrence IS
  'Fase 11: linha do tempo append-only; occurrence_count conta somente failure_observed.';
COMMENT ON TABLE public.notification_outbox IS
  'Fase 11: outbox interno/sintético; in_app e mock_email, sem consumidor de entrega externa.';
