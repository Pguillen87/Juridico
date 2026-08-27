-- Fase 9: scheduler, fila PostgreSQL, worker backend-only e snapshots.
-- Esta migration é aditiva, não edita as migrations publicadas da Fase 8.
SET lock_timeout = '2s';

-- A constraint publicada da Fase 6 mantinha todo monitoramento pausado. A Fase 9
-- prepara o estado ativo, mas não cria seed nem ativa qualquer processo.
ALTER TABLE public.legal_process
  DROP CONSTRAINT IF EXISTS legal_process_monitoring_status_check;
ALTER TABLE public.legal_process
  ADD CONSTRAINT legal_process_monitoring_status_check
  CHECK (monitoring_status IN ('paused', 'active'));

CREATE TABLE public.monitoring_configuration (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  timezone TEXT NOT NULL CHECK (char_length(btrim(timezone)) BETWEEN 1 AND 80),
  active BOOLEAN NOT NULL DEFAULT false,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by UUID REFERENCES public.user_profile(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, version)
);

CREATE UNIQUE INDEX monitoring_configuration_one_active_idx
  ON public.monitoring_configuration (office_id)
  WHERE active = true;

CREATE TABLE public.monitoring_schedule (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  monitoring_configuration_id UUID NOT NULL,
  local_time TIME NOT NULL,
  timezone TEXT NOT NULL CHECK (char_length(btrim(timezone)) BETWEEN 1 AND 80),
  days_of_week INTEGER[] NOT NULL,
  active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, monitoring_configuration_id, local_time, days_of_week),
  FOREIGN KEY (office_id, monitoring_configuration_id)
    REFERENCES public.monitoring_configuration(office_id, id)
    ON DELETE RESTRICT,
  CHECK (cardinality(days_of_week) BETWEEN 1 AND 7),
  CHECK (days_of_week <@ ARRAY[1, 2, 3, 4, 5, 6, 7]::INTEGER[])
);

CREATE INDEX monitoring_schedule_due_idx
  ON public.monitoring_schedule (office_id, active, timezone, local_time);

CREATE TABLE public.query_job (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  process_id UUID NOT NULL,
  provider_id TEXT NOT NULL CHECK (provider_id = 'datajud_sandbox'),
  capability TEXT NOT NULL CHECK (capability = 'process_observation'),
  job_kind TEXT NOT NULL CHECK (job_kind IN ('scheduled', 'manual_reprocess')),
  scheduled_window_utc TIMESTAMPTZ,
  idempotency_key TEXT NOT NULL CHECK (char_length(btrim(idempotency_key)) BETWEEN 1 AND 240),
  request_fingerprint TEXT NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  correlation_id TEXT NOT NULL CHECK (correlation_id ~ '^[A-Za-z0-9._:-]{1,200}$'),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'retry_scheduled', 'succeeded', 'terminal_failure', 'cancelled')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 3),
  max_attempts INTEGER NOT NULL DEFAULT 3 CHECK (max_attempts = 3),
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  lease_token UUID,
  lease_expires_at TIMESTAMPTZ,
  locked_by TEXT CHECK (locked_by IS NULL OR locked_by ~ '^[A-Za-z0-9._:-]{1,120}$'),
  created_by UUID REFERENCES public.user_profile(id) ON DELETE RESTRICT,
  last_error_code TEXT CHECK (last_error_code IS NULL OR char_length(btrim(last_error_code)) BETWEEN 1 AND 100),
  last_error_message TEXT CHECK (last_error_message IS NULL OR char_length(last_error_message) BETWEEN 1 AND 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  UNIQUE (office_id, id),
  UNIQUE (office_id, idempotency_key),
  FOREIGN KEY (office_id, process_id)
    REFERENCES public.legal_process(office_id, id)
    ON DELETE RESTRICT,
  CHECK (
    (job_kind = 'scheduled' AND scheduled_window_utc IS NOT NULL)
    OR (job_kind = 'manual_reprocess' AND scheduled_window_utc IS NULL)
  ),
  CHECK (
    (status = 'running'
      AND lease_token IS NOT NULL
      AND lease_expires_at IS NOT NULL
      AND locked_by IS NOT NULL)
    OR (status <> 'running'
      AND lease_token IS NULL
      AND lease_expires_at IS NULL
      AND locked_by IS NULL)
  ),
  CHECK (attempt_count <= max_attempts),
  CHECK ((status IN ('succeeded', 'terminal_failure', 'cancelled') AND finished_at IS NOT NULL)
    OR status NOT IN ('succeeded', 'terminal_failure', 'cancelled'))
);

CREATE INDEX query_job_claim_idx
  ON public.query_job (status, available_at, lease_expires_at, created_at);
CREATE INDEX query_job_process_idx
  ON public.query_job (office_id, process_id, status, created_at DESC);
CREATE INDEX query_job_failure_idx
  ON public.query_job (office_id, status, last_error_code, updated_at DESC);

CREATE TABLE public.query_execution (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  query_job_id UUID NOT NULL,
  process_id UUID NOT NULL,
  provider_id TEXT NOT NULL CHECK (provider_id = 'datajud_sandbox'),
  capability TEXT NOT NULL CHECK (capability = 'process_observation'),
  attempt_number INTEGER NOT NULL CHECK (attempt_number BETWEEN 1 AND 3),
  status TEXT NOT NULL DEFAULT 'running'
    CHECK (status IN ('running', 'succeeded', 'retry_scheduled', 'terminal_failure', 'cancelled')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms BETWEEN 0 AND 86400000),
  http_status INTEGER CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
  provider_exchange_id UUID,
  error_code TEXT CHECK (error_code IS NULL OR char_length(btrim(error_code)) BETWEEN 1 AND 100),
  error_message_sanitized TEXT CHECK (error_message_sanitized IS NULL OR char_length(error_message_sanitized) BETWEEN 1 AND 1000),
  correlation_id TEXT NOT NULL CHECK (correlation_id ~ '^[A-Za-z0-9._:-]{1,200}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, query_job_id, attempt_number),
  UNIQUE (office_id, correlation_id),
  FOREIGN KEY (office_id, query_job_id)
    REFERENCES public.query_job(office_id, id)
    ON DELETE RESTRICT,
  FOREIGN KEY (office_id, process_id)
    REFERENCES public.legal_process(office_id, id)
    ON DELETE RESTRICT,
  FOREIGN KEY (office_id, provider_exchange_id)
    REFERENCES public.provider_exchange(office_id, id)
    ON DELETE RESTRICT,
  CHECK ((status = 'running' AND finished_at IS NULL)
    OR (status <> 'running' AND finished_at IS NOT NULL)),
  CHECK ((status = 'succeeded' AND provider_exchange_id IS NOT NULL)
    OR status IN ('retry_scheduled', 'terminal_failure', 'cancelled', 'running'))
);

CREATE INDEX query_execution_process_idx
  ON public.query_execution (office_id, process_id, started_at DESC);
CREATE INDEX query_execution_status_idx
  ON public.query_execution (office_id, status, started_at DESC);
CREATE INDEX query_execution_job_idx
  ON public.query_execution (office_id, query_job_id, attempt_number DESC);

CREATE TABLE public.process_snapshot (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  process_id UUID NOT NULL,
  query_execution_id UUID NOT NULL,
  provider_id TEXT NOT NULL CHECK (provider_id = 'datajud_sandbox'),
  source TEXT NOT NULL CHECK (source = 'datajud'),
  normalizer_version TEXT NOT NULL CHECK (char_length(btrim(normalizer_version)) BETWEEN 1 AND 80),
  normalized_data JSONB NOT NULL,
  missing_fields JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(missing_fields) = 'array'),
  snapshot_hash TEXT NOT NULL CHECK (snapshot_hash ~ '^[0-9a-f]{64}$'),
  evidence_ref TEXT CHECK (evidence_ref IS NULL OR char_length(btrim(evidence_ref)) BETWEEN 1 AND 240),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, query_execution_id),
  FOREIGN KEY (office_id, process_id)
    REFERENCES public.legal_process(office_id, id)
    ON DELETE RESTRICT,
  FOREIGN KEY (office_id, query_execution_id)
    REFERENCES public.query_execution(office_id, id)
    ON DELETE RESTRICT,
  CHECK (jsonb_typeof(normalized_data) = 'object'),
  CHECK (NOT public.provider_json_has_comparison(normalized_data)),
  CHECK (NOT public.provider_payload_has_sensitive_key(normalized_data))
);

CREATE INDEX process_snapshot_process_idx
  ON public.process_snapshot (office_id, process_id, created_at DESC);
CREATE INDEX process_snapshot_hash_idx
  ON public.process_snapshot (office_id, process_id, snapshot_hash);

CREATE OR REPLACE FUNCTION public.phase9_block_query_job_direct_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase9_internal', true) <> '1' THEN
    RAISE EXCEPTION 'query_job is writable only through phase 9 domain functions'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'query_job is append-only for physical deletion'
      USING ERRCODE = '42501';
  END IF;
  IF OLD.id IS DISTINCT FROM NEW.id
     OR OLD.office_id IS DISTINCT FROM NEW.office_id
     OR OLD.process_id IS DISTINCT FROM NEW.process_id
     OR OLD.provider_id IS DISTINCT FROM NEW.provider_id
     OR OLD.capability IS DISTINCT FROM NEW.capability
     OR OLD.job_kind IS DISTINCT FROM NEW.job_kind
     OR OLD.scheduled_window_utc IS DISTINCT FROM NEW.scheduled_window_utc
     OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
     OR OLD.request_fingerprint IS DISTINCT FROM NEW.request_fingerprint
     OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
     OR OLD.created_by IS DISTINCT FROM NEW.created_by
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
  THEN
    RAISE EXCEPTION 'query_job identity is immutable' USING ERRCODE = '42501';
  END IF;
  IF OLD.status = 'pending' AND NEW.status NOT IN ('pending', 'running', 'cancelled')
     OR OLD.status = 'retry_scheduled' AND NEW.status NOT IN ('retry_scheduled', 'running', 'cancelled')
     OR OLD.status = 'running' AND NEW.status NOT IN ('running', 'retry_scheduled', 'succeeded', 'terminal_failure', 'cancelled')
     OR OLD.status IN ('succeeded', 'terminal_failure', 'cancelled') AND NEW.status IS DISTINCT FROM OLD.status
  THEN
    RAISE EXCEPTION 'invalid query_job state transition' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase9_block_query_execution_direct_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase9_internal', true) <> '1' THEN
    RAISE EXCEPTION 'query_execution is writable only through phase 9 domain functions'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'query_execution is append-only for physical deletion'
      USING ERRCODE = '42501';
  END IF;
  IF OLD.id IS DISTINCT FROM NEW.id
     OR OLD.office_id IS DISTINCT FROM NEW.office_id
     OR OLD.query_job_id IS DISTINCT FROM NEW.query_job_id
     OR OLD.process_id IS DISTINCT FROM NEW.process_id
     OR OLD.provider_id IS DISTINCT FROM NEW.provider_id
     OR OLD.capability IS DISTINCT FROM NEW.capability
     OR OLD.attempt_number IS DISTINCT FROM NEW.attempt_number
     OR OLD.started_at IS DISTINCT FROM NEW.started_at
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
     OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
     OR (OLD.provider_exchange_id IS NOT NULL AND OLD.provider_exchange_id IS DISTINCT FROM NEW.provider_exchange_id)
  THEN
    RAISE EXCEPTION 'query_execution identity is immutable' USING ERRCODE = '42501';
  END IF;
  IF OLD.status = 'running' AND NEW.status NOT IN ('running', 'succeeded', 'retry_scheduled', 'terminal_failure', 'cancelled')
     OR OLD.status <> 'running' AND NEW.status IS DISTINCT FROM OLD.status
  THEN
    RAISE EXCEPTION 'invalid query_execution state transition' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase9_block_snapshot_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'process_snapshot is immutable and append-only'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER phase9_query_job_guard
BEFORE UPDATE OR DELETE ON public.query_job
FOR EACH ROW EXECUTE FUNCTION public.phase9_block_query_job_direct_mutation();

CREATE TRIGGER phase9_query_execution_guard
BEFORE UPDATE OR DELETE ON public.query_execution
FOR EACH ROW EXECUTE FUNCTION public.phase9_block_query_execution_direct_mutation();

CREATE TRIGGER phase9_snapshot_guard
BEFORE UPDATE OR DELETE ON public.process_snapshot
FOR EACH ROW EXECUTE FUNCTION public.phase9_block_snapshot_mutation();

ALTER TABLE public.monitoring_configuration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monitoring_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.query_job ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.query_execution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.process_snapshot ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.monitoring_configuration, public.monitoring_schedule,
  public.query_job, public.query_execution, public.process_snapshot
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.monitoring_configuration, public.monitoring_schedule,
  public.query_job, public.query_execution, public.process_snapshot
  TO authenticated;

CREATE POLICY monitoring_configuration_select_same_office
ON public.monitoring_configuration
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

CREATE POLICY monitoring_schedule_select_same_office
ON public.monitoring_schedule
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

CREATE POLICY query_job_select_same_office
ON public.query_job
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

CREATE POLICY query_execution_select_same_office
ON public.query_execution
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

CREATE POLICY process_snapshot_select_same_office
ON public.process_snapshot
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

CREATE OR REPLACE FUNCTION public.phase9_timezone_is_valid(p_timezone TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names
    WHERE name = p_timezone
  );
$$;

CREATE OR REPLACE FUNCTION public.phase9_write_system_audit(
  p_action TEXT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_office_id UUID,
  p_metadata JSONB,
  p_origin TEXT,
  p_worker_id TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  audit_id BIGINT;
  metadata_key TEXT;
BEGIN
  IF p_action NOT IN (
    'query_job.created', 'query_job.claimed', 'query_execution.started',
    'query_execution.completed', 'query_job.retry_scheduled',
    'query_job.terminal_failure', 'query_job.lease_recovered',
    'query_job.cancelled', 'process_snapshot.created',
    'provider.exchange.recorded', 'provider.payload.recorded',
    'monitoring.configuration.updated', 'monitoring.schedule.updated'
  ) THEN
    RAISE EXCEPTION 'phase 9 system audit action is not allowlisted'
      USING ERRCODE = '22023';
  END IF;
  IF p_origin NOT IN ('system_scheduler', 'system_worker') THEN
    RAISE EXCEPTION 'phase 9 system audit origin is not allowlisted'
      USING ERRCODE = '22023';
  END IF;
  IF p_office_id IS NULL OR p_metadata IS NULL OR jsonb_typeof(p_metadata) <> 'object' THEN
    RAISE EXCEPTION 'invalid phase 9 system audit input' USING ERRCODE = '22023';
  END IF;
  IF p_worker_id IS NOT NULL AND p_worker_id !~ '^[A-Za-z0-9._:-]{1,120}$' THEN
    RAISE EXCEPTION 'invalid phase 9 worker identifier' USING ERRCODE = '22023';
  END IF;
  FOR metadata_key IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF metadata_key NOT IN (
      'origin', 'worker_id', 'provider_id', 'job_kind', 'result_kind',
      'status', 'error_code', 'attempt_number', 'scheduled_window_utc',
      'retry_after_ms', 'snapshot_hash', 'payload_hash', 'payload_bytes',
      'http_status', 'reason'
    ) THEN
      RAISE EXCEPTION 'phase 9 system audit metadata key is not allowlisted'
        USING ERRCODE = '22023';
    END IF;
  END LOOP;
  IF p_entity_type NOT IN (
    'query_job', 'query_execution', 'process_snapshot',
    'provider_exchange', 'raw_provider_payload',
    'monitoring_configuration', 'monitoring_schedule'
  ) THEN
    RAISE EXCEPTION 'phase 9 system audit entity is not allowlisted'
      USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.audit_log (
    audit_scope, office_id, actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    'operational', p_office_id, NULL, p_action, p_entity_type, p_entity_id,
    p_metadata || jsonb_build_object('origin', p_origin)
      || CASE WHEN p_worker_id IS NULL THEN '{}'::jsonb
              ELSE jsonb_build_object('worker_id', p_worker_id) END
  ) RETURNING id INTO audit_id;
  RETURN audit_id;
END;
$$;

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
  IF p_action NOT IN ('process.monitoring.updated', 'query_job.manual_reprocess_requested') THEN
    RAISE EXCEPTION 'phase 9 user audit action is not allowlisted' USING ERRCODE = '22023';
  END IF;
  IF (p_action = 'process.monitoring.updated' AND p_entity_type <> 'legal_process')
     OR (p_action = 'query_job.manual_reprocess_requested' AND p_entity_type <> 'query_job') THEN
    RAISE EXCEPTION 'phase 9 user audit entity mismatch' USING ERRCODE = '22023';
  END IF;
  IF p_metadata IS NULL OR jsonb_typeof(p_metadata) <> 'object' THEN
    RAISE EXCEPTION 'invalid phase 9 user audit metadata' USING ERRCODE = '22023';
  END IF;
  FOR metadata_key IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF metadata_key NOT IN ('before_status', 'after_status', 'failed_job_id', 'idempotency_key') THEN
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

CREATE OR REPLACE FUNCTION public.phase9_upsert_monitoring_configuration(
  p_office_id UUID,
  p_timezone TEXT,
  p_active BOOLEAN,
  p_version INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  configuration_id UUID;
BEGIN
  IF p_office_id IS NULL OR p_version IS NULL OR p_version < 1
     OR NOT public.phase9_timezone_is_valid(p_timezone) THEN
    RAISE EXCEPTION 'invalid monitoring configuration' USING ERRCODE = '22023';
  END IF;
  PERFORM 1 FROM public.office WHERE id = p_office_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'office is not active' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('juridico.phase9_internal', '1', true);
  IF p_active THEN
    UPDATE public.monitoring_configuration
       SET active = false, updated_at = clock_timestamp()
     WHERE office_id = p_office_id AND active = true;
  END IF;
  INSERT INTO public.monitoring_configuration (
    office_id, timezone, active, version
  ) VALUES (
    p_office_id, btrim(p_timezone), p_active, p_version
  )
  ON CONFLICT (office_id, version) DO UPDATE SET
    timezone = EXCLUDED.timezone,
    active = EXCLUDED.active,
    updated_at = clock_timestamp()
  RETURNING id INTO configuration_id;
  PERFORM public.phase9_write_system_audit(
    'monitoring.configuration.updated', 'monitoring_configuration', configuration_id,
    p_office_id,
    jsonb_build_object('status', CASE WHEN p_active THEN 'active' ELSE 'paused' END),
    'system_scheduler'
  );
  RETURN configuration_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase9_upsert_monitoring_schedule(
  p_configuration_id UUID,
  p_local_time TIME,
  p_timezone TEXT,
  p_days_of_week INTEGER[],
  p_active BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  office_uuid UUID;
  schedule_id UUID;
  normalized_days INTEGER[];
BEGIN
  IF p_local_time IS NULL OR NOT public.phase9_timezone_is_valid(p_timezone)
     OR p_days_of_week IS NULL OR cardinality(p_days_of_week) < 1 THEN
    RAISE EXCEPTION 'invalid monitoring schedule' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(p_days_of_week) AS d(day)
    WHERE d.day < 1 OR d.day > 7
  ) THEN
    RAISE EXCEPTION 'invalid monitoring schedule day' USING ERRCODE = '22023';
  END IF;
  SELECT office_id INTO office_uuid
    FROM public.monitoring_configuration
   WHERE id = p_configuration_id;
  IF office_uuid IS NULL THEN
    RAISE EXCEPTION 'monitoring configuration not found' USING ERRCODE = '42501';
  END IF;
  normalized_days := ARRAY(
    SELECT DISTINCT d.day FROM unnest(p_days_of_week) AS d(day) ORDER BY d.day
  );
  PERFORM set_config('juridico.phase9_internal', '1', true);
  INSERT INTO public.monitoring_schedule (
    office_id, monitoring_configuration_id, local_time, timezone,
    days_of_week, active
  ) VALUES (
    office_uuid, p_configuration_id, p_local_time, btrim(p_timezone),
    normalized_days, p_active
  )
  ON CONFLICT (office_id, monitoring_configuration_id, local_time, days_of_week)
  DO UPDATE SET timezone = EXCLUDED.timezone,
                active = EXCLUDED.active,
                updated_at = clock_timestamp()
  RETURNING id INTO schedule_id;
  PERFORM public.phase9_write_system_audit(
    'monitoring.schedule.updated', 'monitoring_schedule', schedule_id,
    office_uuid,
    jsonb_build_object('status', CASE WHEN p_active THEN 'active' ELSE 'paused' END),
    'system_scheduler'
  );
  RETURN schedule_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase9_set_process_monitoring_status(
  p_process_id UUID,
  p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  process_row public.legal_process%ROWTYPE;
  previous_status TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('paused', 'active') THEN
    RAISE EXCEPTION 'invalid monitoring status' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO process_row
    FROM public.legal_process
   WHERE id = p_process_id AND office_id = actor.actor_office_id
   FOR UPDATE;
  IF process_row.id IS NULL OR process_row.status <> 'active' THEN
    RAISE EXCEPTION 'process is not active in actor office' USING ERRCODE = '42501';
  END IF;
  IF p_status = 'active' AND process_row.is_public IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'sealed process cannot be monitored automatically' USING ERRCODE = '42501';
  END IF;
  previous_status := process_row.monitoring_status;
  IF previous_status IS DISTINCT FROM p_status THEN
    PERFORM set_config('juridico.phase9_internal', '1', true);
    UPDATE public.legal_process
       SET monitoring_status = p_status, updated_at = clock_timestamp()
     WHERE id = p_process_id AND office_id = actor.actor_office_id;
    PERFORM public.phase9_write_user_audit(
      'process.monitoring.updated', 'legal_process', p_process_id,
      jsonb_build_object('before_status', previous_status, 'after_status', p_status)
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase9_scheduler_tick(
  p_as_of TIMESTAMPTZ,
  p_window_tolerance_seconds INTEGER DEFAULT 300
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  schedule_row RECORD;
  process_row RECORD;
  local_now TIMESTAMP;
  window_local TIMESTAMP;
  window_utc TIMESTAMPTZ;
  idempotency TEXT;
  job_id UUID;
  created_count INTEGER := 0;
BEGIN
  IF p_as_of IS NULL OR p_window_tolerance_seconds < 0 OR p_window_tolerance_seconds > 900 THEN
    RAISE EXCEPTION 'invalid scheduler tick' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('juridico.phase9_internal', '1', true);
  FOR schedule_row IN
    SELECT s.*, mc.timezone AS configuration_timezone, mc.active AS configuration_active
      FROM public.monitoring_schedule s
      JOIN public.monitoring_configuration mc
        ON mc.id = s.monitoring_configuration_id
       AND mc.office_id = s.office_id
     WHERE s.active = true AND mc.active = true
  LOOP
    local_now := p_as_of AT TIME ZONE schedule_row.timezone;
    IF extract(isodow FROM local_now)::INTEGER <> ALL(schedule_row.days_of_week)
       OR local_now::TIME < schedule_row.local_time
       OR local_now::TIME >= schedule_row.local_time
          + (p_window_tolerance_seconds * INTERVAL '1 second') THEN
      CONTINUE;
    END IF;
    window_local := local_now::DATE + schedule_row.local_time;
    window_utc := window_local AT TIME ZONE schedule_row.timezone;
    IF window_utc > p_as_of THEN
      CONTINUE;
    END IF;
    FOR process_row IN
      SELECT lp.id, lp.office_id, lp.cnj_number
        FROM public.legal_process lp
       WHERE lp.office_id = schedule_row.office_id
         AND lp.status = 'active'
         AND lp.is_public = true
         AND lp.monitoring_status = 'active'
    LOOP
      idempotency := format(
        'scheduled:%s:datajud_sandbox:process_observation:%s',
        process_row.id, window_utc::TEXT
      );
      INSERT INTO public.query_job (
        office_id, process_id, provider_id, capability, job_kind,
        scheduled_window_utc, idempotency_key, request_fingerprint,
        correlation_id, status, attempt_count, max_attempts, available_at
      ) VALUES (
        process_row.office_id, process_row.id, 'datajud_sandbox',
        'process_observation', 'scheduled', window_utc,
        idempotency,
        encode(extensions.digest(convert_to(idempotency, 'UTF8'), 'sha256'), 'hex'),
        replace(gen_random_uuid()::TEXT, '-', ''), 'pending', 0, 3, clock_timestamp()
      )
      ON CONFLICT (office_id, idempotency_key) DO NOTHING
      RETURNING id INTO job_id;
      IF job_id IS NOT NULL THEN
        created_count := created_count + 1;
        PERFORM public.phase9_write_system_audit(
          'query_job.created', 'query_job', job_id, process_row.office_id,
          jsonb_build_object(
            'provider_id', 'datajud_sandbox',
            'job_kind', 'scheduled',
            'scheduled_window_utc', window_utc::TEXT
          ),
          'system_scheduler'
        );
      END IF;
      job_id := NULL;
    END LOOP;
  END LOOP;
  RETURN created_count;
END;
$$;

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
     OR process_row.monitoring_status <> 'active' THEN
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

CREATE OR REPLACE FUNCTION public.phase9_renew_query_job_lease(
  p_job_id UUID,
  p_execution_id UUID,
  p_lease_token UUID,
  p_lease_duration_ms INTEGER DEFAULT 30000
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  changed BOOLEAN;
BEGIN
  IF p_job_id IS NULL OR p_execution_id IS NULL OR p_lease_token IS NULL
     OR p_lease_duration_ms <= 15000 OR p_lease_duration_ms > 120000 THEN
    RAISE EXCEPTION 'invalid lease renewal input' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('juridico.phase9_internal', '1', true);
  UPDATE public.query_job j
     SET lease_expires_at = clock_timestamp() + (p_lease_duration_ms * INTERVAL '1 millisecond'),
         updated_at = clock_timestamp()
   WHERE j.id = p_job_id
     AND j.status = 'running'
     AND j.lease_token = p_lease_token
     AND j.lease_expires_at > clock_timestamp()
     AND EXISTS (
       SELECT 1 FROM public.query_execution e
        WHERE e.id = p_execution_id
          AND e.query_job_id = j.id
          AND e.status = 'running'
     );
  changed := FOUND;
  RETURN changed;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase9_recover_expired_query_jobs(
  p_limit INTEGER DEFAULT 100
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  job_row RECORD;
  execution_row RECORD;
  recovered_count INTEGER := 0;
  next_status TEXT;
  next_at TIMESTAMPTZ;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 1000 THEN
    RAISE EXCEPTION 'invalid expired job recovery limit' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('juridico.phase9_internal', '1', true);
  FOR job_row IN
    SELECT j.* FROM public.query_job j
     WHERE j.status = 'running'
       AND j.lease_expires_at <= clock_timestamp()
     ORDER BY j.lease_expires_at, j.id
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  LOOP
    SELECT e.* INTO execution_row
      FROM public.query_execution e
     WHERE e.query_job_id = job_row.id
       AND e.status = 'running'
     ORDER BY e.attempt_number DESC
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
     WHERE id = job_row.id;
    PERFORM public.phase9_write_system_audit(
      CASE WHEN next_status = 'retry_scheduled'
           THEN 'query_job.lease_recovered'
           ELSE 'query_job.terminal_failure' END,
      'query_job', job_row.id, job_row.office_id,
      jsonb_build_object('error_code', 'worker_lease_expired', 'attempt_number', job_row.attempt_count),
      'system_worker', 'lease-recovery'
    );
    recovered_count := recovered_count + 1;
  END LOOP;
  RETURN recovered_count;
END;
$$;

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

CREATE OR REPLACE FUNCTION public.phase9_request_manual_reprocess(
  p_failed_job_id UUID,
  p_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  failed_job public.query_job%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  new_job_id UUID;
  key_value TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_failed_job_id IS NULL OR p_idempotency_key IS NULL
     OR btrim(p_idempotency_key) !~ '^[A-Za-z0-9._:-]{1,120}$' THEN
    RAISE EXCEPTION 'invalid manual reprocess input' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO failed_job
    FROM public.query_job
   WHERE id = p_failed_job_id AND office_id = actor.actor_office_id
   FOR SHARE;
  IF failed_job.id IS NULL OR failed_job.status <> 'terminal_failure' THEN
    RAISE EXCEPTION 'job is not eligible for manual reprocess' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO process_row
    FROM public.legal_process
   WHERE id = failed_job.process_id AND office_id = actor.actor_office_id
   FOR SHARE;
  IF process_row.id IS NULL OR process_row.status <> 'active'
     OR process_row.is_public IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'process is not eligible for manual reprocess' USING ERRCODE = '42501';
  END IF;
  key_value := 'manual-reprocess:' || failed_job.id::TEXT || ':' || btrim(p_idempotency_key);
  PERFORM set_config('juridico.phase9_internal', '1', true);
  INSERT INTO public.query_job (
    office_id, process_id, provider_id, capability, job_kind,
    scheduled_window_utc, idempotency_key, request_fingerprint,
    correlation_id, status, attempt_count, max_attempts, available_at, created_by
  ) VALUES (
    failed_job.office_id, failed_job.process_id, failed_job.provider_id,
    failed_job.capability, 'manual_reprocess', NULL, key_value,
    encode(extensions.digest(convert_to(key_value, 'UTF8'), 'sha256'), 'hex'),
    replace(gen_random_uuid()::TEXT, '-', ''), 'pending', 0, 3, clock_timestamp(), actor.actor_id
  )
  ON CONFLICT (office_id, idempotency_key) DO NOTHING
  RETURNING id INTO new_job_id;
  IF new_job_id IS NULL THEN
    SELECT id INTO new_job_id FROM public.query_job
     WHERE office_id = failed_job.office_id AND idempotency_key = key_value;
    RETURN new_job_id;
  END IF;
  PERFORM public.phase9_write_user_audit(
    'query_job.manual_reprocess_requested', 'query_job', new_job_id,
    jsonb_build_object('failed_job_id', failed_job.id::TEXT,
                       'idempotency_key', btrim(p_idempotency_key))
  );
  RETURN new_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.phase9_timezone_is_valid(TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase9_write_system_audit(TEXT, TEXT, UUID, UUID, JSONB, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase9_write_user_audit(TEXT, TEXT, UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase9_upsert_monitoring_configuration(UUID, TEXT, BOOLEAN, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase9_upsert_monitoring_schedule(UUID, TIME, TEXT, INTEGER[], BOOLEAN)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase9_scheduler_tick(TIMESTAMPTZ, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase9_claim_query_job(TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase9_renew_query_job_lease(UUID, UUID, UUID, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase9_recover_expired_query_jobs(INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase9_complete_query_execution(UUID, UUID, UUID, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase9_request_manual_reprocess(UUID, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase9_set_process_monitoring_status(UUID, TEXT)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.phase9_set_process_monitoring_status(UUID, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase9_upsert_monitoring_configuration(UUID, TEXT, BOOLEAN, INTEGER)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.phase9_upsert_monitoring_schedule(UUID, TIME, TEXT, INTEGER[], BOOLEAN)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.phase9_scheduler_tick(TIMESTAMPTZ, INTEGER)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.phase9_claim_query_job(TEXT, INTEGER)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.phase9_renew_query_job_lease(UUID, UUID, UUID, INTEGER)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.phase9_recover_expired_query_jobs(INTEGER)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.phase9_complete_query_execution(UUID, UUID, UUID, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, INTEGER)
  TO service_role;

REVOKE ALL ON FUNCTION public.phase9_block_query_job_direct_mutation()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase9_block_query_execution_direct_mutation()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase9_block_snapshot_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.query_job IS
  'Fase 9: obrigação idempotente de consulta; criada e mutada somente por RPCs controladas.';
COMMENT ON TABLE public.query_execution IS
  'Fase 9: histórico imutável de tentativas, concluído somente por worker backend com lease válida.';
COMMENT ON TABLE public.process_snapshot IS
  'Fase 9: snapshot imutável por execução bem-sucedida; comparação pertence à Fase 10.';
