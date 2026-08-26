SET lock_timeout = '2s';

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.provider_json_has_comparison(p_value jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  entry jsonb;
  key_name text;
BEGIN
  IF p_value IS NULL THEN
    RETURN false;
  END IF;
  IF jsonb_typeof(p_value) = 'object' THEN
    FOR key_name, entry IN SELECT key, value FROM jsonb_each(p_value) LOOP
      IF key_name IN ('changed', 'unchanged') THEN
        RETURN true;
      END IF;
      IF public.provider_json_has_comparison(entry) THEN
        RETURN true;
      END IF;
    END LOOP;
  ELSIF jsonb_typeof(p_value) = 'array' THEN
    FOR entry IN SELECT value FROM jsonb_array_elements(p_value) LOOP
      IF public.provider_json_has_comparison(entry) THEN
        RETURN true;
      END IF;
    END LOOP;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.provider_payload_has_sensitive_key(p_value jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  entry jsonb;
  key_name text;
BEGIN
  IF p_value IS NULL THEN
    RETURN false;
  END IF;
  IF jsonb_typeof(p_value) = 'object' THEN
    FOR key_name, entry IN SELECT key, value FROM jsonb_each(p_value) LOOP
      IF lower(key_name) ~ '^(authorization|api[_-]?key|token|access[_-]?token|refresh[_-]?token|cookie|set-cookie|password|secret|client[_-]?secret|service[_-]?role)$' THEN
        RETURN true;
      END IF;
      IF jsonb_typeof(entry) = 'string'
         AND entry #>> '{}' ~* '^[a-z][a-z0-9+.-]*://[^/]*:[^/@]+@' THEN
        RETURN true;
      END IF;
      IF public.provider_payload_has_sensitive_key(entry) THEN
        RETURN true;
      END IF;
    END LOOP;
  ELSIF jsonb_typeof(p_value) = 'array' THEN
    FOR entry IN SELECT value FROM jsonb_array_elements(p_value) LOOP
      IF public.provider_payload_has_sensitive_key(entry) THEN
        RETURN true;
      END IF;
    END LOOP;
  END IF;
  RETURN false;
END;
$$;

CREATE TABLE public.provider_exchange (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  process_id UUID NOT NULL,
  provider_id TEXT NOT NULL CHECK (provider_id IN ('datajud_sandbox', 'manual_observation')),
  source TEXT NOT NULL CHECK (source IN ('datajud', 'manual')),
  contract_version INTEGER NOT NULL CHECK (contract_version = 1),
  subject_ref TEXT NOT NULL CHECK (char_length(btrim(subject_ref)) BETWEEN 1 AND 200),
  correlation_id TEXT NOT NULL CHECK (char_length(btrim(correlation_id)) BETWEEN 1 AND 200),
  request_fingerprint TEXT NOT NULL CHECK (char_length(btrim(request_fingerprint)) BETWEEN 1 AND 200),
  result_kind TEXT NOT NULL CHECK (result_kind IN ('observation', 'failure')),
  result_status TEXT NOT NULL CHECK (result_status IN ('observed', 'not_found', 'not_supported', 'rate_limited', 'timeout', 'source_unavailable', 'technical_failure', 'manual_review_required')),
  error_code TEXT CHECK (error_code IS NULL OR char_length(btrim(error_code)) BETWEEN 1 AND 100),
  normalized_result JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, correlation_id),
  FOREIGN KEY (office_id, process_id) REFERENCES public.legal_process(office_id, id) ON DELETE RESTRICT,
  CHECK (
    (result_kind = 'observation' AND result_status = 'observed' AND error_code IS NULL AND normalized_result IS NOT NULL)
    OR
    (result_kind = 'failure' AND result_status <> 'observed' AND error_code IS NOT NULL AND normalized_result IS NULL)
  ),
  CHECK (normalized_result IS NULL OR jsonb_typeof(normalized_result) = 'object'),
  CHECK (normalized_result IS NULL OR NOT public.provider_json_has_comparison(normalized_result)),
  CHECK (provider_id <> 'manual_observation' OR source = 'manual'),
  CHECK (provider_id <> 'datajud_sandbox' OR source = 'datajud')
);

CREATE INDEX provider_exchange_process_idx
  ON public.provider_exchange (office_id, process_id, created_at DESC);
CREATE INDEX provider_exchange_provider_idx
  ON public.provider_exchange (office_id, provider_id, created_at DESC);
CREATE INDEX provider_exchange_request_idx
  ON public.provider_exchange (office_id, request_fingerprint);

CREATE TABLE public.raw_provider_payload (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_exchange_id UUID NOT NULL,
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  process_id UUID NOT NULL,
  provider_id TEXT NOT NULL CHECK (provider_id IN ('datajud_sandbox', 'manual_observation')),
  source TEXT NOT NULL CHECK (source IN ('datajud', 'manual')),
  correlation_id TEXT NOT NULL CHECK (char_length(btrim(correlation_id)) BETWEEN 1 AND 200),
  sanitization_version TEXT NOT NULL CHECK (char_length(btrim(sanitization_version)) BETWEEN 1 AND 80),
  payload JSONB NOT NULL,
  payload_hash TEXT NOT NULL CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
  payload_bytes INTEGER NOT NULL CHECK (payload_bytes BETWEEN 1 AND 262144),
  received_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider_exchange_id),
  UNIQUE (office_id, id),
  FOREIGN KEY (office_id, provider_exchange_id) REFERENCES public.provider_exchange(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, process_id) REFERENCES public.legal_process(office_id, id) ON DELETE RESTRICT,
  CHECK (jsonb_typeof(payload) IN ('object', 'array')),
  CHECK (octet_length(convert_to(payload::text, 'UTF8')) = payload_bytes),
  CHECK (octet_length(convert_to(payload::text, 'UTF8')) <= 262144),
  CHECK (NOT public.provider_payload_has_sensitive_key(payload)),
  CHECK (NOT public.provider_json_has_comparison(payload))
);

CREATE INDEX raw_provider_payload_office_received_idx
  ON public.raw_provider_payload (office_id, received_at DESC);
CREATE INDEX raw_provider_payload_process_idx
  ON public.raw_provider_payload (office_id, process_id, received_at DESC);
CREATE INDEX raw_provider_payload_hash_idx
  ON public.raw_provider_payload (payload_hash);

CREATE OR REPLACE FUNCTION public.provider_payload_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  exchange_row public.provider_exchange%ROWTYPE;
  expected_hash text;
  expected_bytes integer;
BEGIN
  SELECT * INTO exchange_row
    FROM public.provider_exchange
   WHERE id = NEW.provider_exchange_id
     AND office_id = NEW.office_id;
  IF exchange_row.id IS NULL THEN
    RAISE EXCEPTION 'provider exchange not found' USING ERRCODE = '23503';
  END IF;
  IF NEW.process_id IS DISTINCT FROM exchange_row.process_id
     OR NEW.provider_id IS DISTINCT FROM exchange_row.provider_id
     OR NEW.source IS DISTINCT FROM exchange_row.source
     OR NEW.correlation_id IS DISTINCT FROM exchange_row.correlation_id THEN
    RAISE EXCEPTION 'raw provider payload does not match exchange' USING ERRCODE = '23514';
  END IF;
  expected_bytes := octet_length(convert_to(NEW.payload::text, 'UTF8'));
  expected_hash := encode(extensions.digest(convert_to(NEW.payload::text, 'UTF8'), 'sha256'), 'hex');
  IF NEW.payload_bytes IS DISTINCT FROM expected_bytes
     OR NEW.payload_hash IS DISTINCT FROM expected_hash THEN
    RAISE EXCEPTION 'raw provider payload integrity mismatch' USING ERRCODE = '23514';
  END IF;
  IF NEW.received_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'raw provider payload timestamp is invalid' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER provider_payload_integrity_before_insert
BEFORE INSERT ON public.raw_provider_payload
FOR EACH ROW EXECUTE FUNCTION public.provider_payload_integrity();

CREATE OR REPLACE FUNCTION public.prevent_provider_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'provider records are append-only' USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER provider_exchange_append_only
BEFORE UPDATE OR DELETE ON public.provider_exchange
FOR EACH ROW EXECUTE FUNCTION public.prevent_provider_immutable_mutation();

CREATE TRIGGER raw_provider_payload_append_only
BEFORE UPDATE OR DELETE ON public.raw_provider_payload
FOR EACH ROW EXECUTE FUNCTION public.prevent_provider_immutable_mutation();

CREATE OR REPLACE FUNCTION public.write_provider_audit(
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
  allowed_key TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF p_action NOT IN ('provider.exchange.recorded', 'provider.payload.recorded', 'provider.manual.recorded') THEN
    RAISE EXCEPTION 'provider audit action is not allowlisted' USING ERRCODE = '22023';
  END IF;
  IF (p_action = 'provider.exchange.recorded' AND p_entity_type <> 'provider_exchange')
     OR (p_action = 'provider.payload.recorded' AND p_entity_type <> 'raw_provider_payload')
     OR (p_action = 'provider.manual.recorded' AND p_entity_type <> 'provider_exchange') THEN
    RAISE EXCEPTION 'provider audit entity mismatch' USING ERRCODE = '22023';
  END IF;
  IF p_metadata IS NULL OR jsonb_typeof(p_metadata) <> 'object' THEN
    RAISE EXCEPTION 'invalid provider audit metadata' USING ERRCODE = '22023';
  END IF;
  FOR allowed_key IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF allowed_key NOT IN ('provider_id', 'source', 'result_kind', 'status', 'error_code', 'correlation_id', 'payload_hash', 'payload_bytes') THEN
      RAISE EXCEPTION 'provider audit metadata key is not allowlisted' USING ERRCODE = '22023';
    END IF;
  END LOOP;
  INSERT INTO public.audit_log (
    audit_scope,
    office_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  ) VALUES (
    'operational',
    actor.actor_office_id,
    actor.actor_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_metadata
  ) RETURNING id INTO audit_id;
  RETURN audit_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_provider_process_eligible(p_process_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  process_row public.legal_process%ROWTYPE;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO process_row
    FROM public.legal_process
   WHERE id = p_process_id
     AND office_id = actor.actor_office_id
   FOR SHARE;
  IF process_row.id IS NULL OR process_row.status <> 'active' OR process_row.is_public IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'process is not eligible for automatic provider observation' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_provider_exchange(
  p_process_id UUID,
  p_provider_id TEXT,
  p_source TEXT,
  p_contract_version INTEGER,
  p_subject_ref TEXT,
  p_correlation_id TEXT,
  p_request_fingerprint TEXT,
  p_result_kind TEXT,
  p_result_status TEXT,
  p_error_code TEXT DEFAULT NULL,
  p_normalized_result JSONB DEFAULT NULL,
  p_raw_payload JSONB DEFAULT NULL,
  p_sanitization_version TEXT DEFAULT NULL,
  p_received_at TIMESTAMPTZ DEFAULT now()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  process_row public.legal_process%ROWTYPE;
  exchange_id UUID;
  existing_exchange public.provider_exchange%ROWTYPE;
  payload_id UUID;
  payload_hash TEXT;
  payload_bytes INTEGER;
  existing_payload_hash TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_provider_id <> 'datajud_sandbox' OR p_source <> 'datajud' THEN
    RAISE EXCEPTION 'provider exchange is not an approved DataJud sandbox operation' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO process_row
    FROM public.legal_process
   WHERE id = p_process_id
     AND office_id = actor.actor_office_id
   FOR SHARE;
  IF process_row.id IS NULL OR process_row.status <> 'active' OR process_row.is_public IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'process is not eligible for automatic provider observation' USING ERRCODE = '42501';
  END IF;

  IF p_contract_version <> 1
     OR p_process_id IS NULL
     OR p_subject_ref IS NULL OR char_length(btrim(p_subject_ref)) NOT BETWEEN 1 AND 200
     OR p_correlation_id IS NULL OR char_length(btrim(p_correlation_id)) NOT BETWEEN 1 AND 200
     OR p_request_fingerprint IS NULL OR char_length(btrim(p_request_fingerprint)) NOT BETWEEN 1 AND 200
     OR btrim(p_correlation_id) !~ '^[A-Za-z0-9._:-]{1,200}$'
     OR btrim(p_request_fingerprint) !~ '^[A-Za-z0-9._:-]{1,200}$'
     OR p_result_kind NOT IN ('observation', 'failure')
     OR p_result_status NOT IN ('observed', 'not_found', 'not_supported', 'rate_limited', 'timeout', 'source_unavailable', 'technical_failure', 'manual_review_required')
     OR (p_result_kind = 'observation' AND (p_result_status <> 'observed' OR p_error_code IS NOT NULL OR p_normalized_result IS NULL))
     OR (p_result_kind = 'failure' AND (p_result_status = 'observed' OR p_error_code IS NULL OR p_normalized_result IS NOT NULL))
     OR (p_error_code IS NOT NULL AND p_error_code NOT IN ('datajud_not_found', 'datajud_rate_limited', 'datajud_timeout', 'datajud_source_unavailable', 'datajud_dns_failure', 'datajud_network_failure', 'datajud_http_failure', 'datajud_schema_invalid', 'datajud_payload_too_large', 'datajud_process_mismatch', 'datajud_input_schema_invalid', 'datajud_payload_sanitization_failed', 'provider_persistence_failed'))
     OR (p_normalized_result IS NOT NULL AND (
       jsonb_typeof(p_normalized_result) <> 'object'
       OR public.provider_json_has_comparison(p_normalized_result)
       OR public.provider_payload_has_sensitive_key(p_normalized_result)
       OR p_normalized_result->>'kind' <> 'observation'
       OR p_normalized_result->'provider'->>'providerId' <> p_provider_id
       OR p_normalized_result->>'source' <> p_source
       OR p_normalized_result->>'contractVersion' <> p_contract_version::text
       OR p_normalized_result->>'correlationId' <> p_correlation_id
       OR p_normalized_result->'data'->>'processRef' <> p_subject_ref
     ))
  THEN
    RAISE EXCEPTION 'invalid provider exchange input' USING ERRCODE = '22023';
  END IF;
  IF p_raw_payload IS NOT NULL THEN
    IF jsonb_typeof(p_raw_payload) NOT IN ('object', 'array')
       OR public.provider_payload_has_sensitive_key(p_raw_payload)
       OR public.provider_json_has_comparison(p_raw_payload) THEN
      RAISE EXCEPTION 'raw provider payload is not safe to persist' USING ERRCODE = '22023';
    END IF;
    payload_bytes := octet_length(convert_to(p_raw_payload::text, 'UTF8'));
    IF payload_bytes < 1 OR payload_bytes > 262144 THEN
      RAISE EXCEPTION 'raw provider payload exceeds the maximum size' USING ERRCODE = '22023';
    END IF;
    payload_hash := encode(extensions.digest(convert_to(p_raw_payload::text, 'UTF8'), 'sha256'), 'hex');
    IF p_sanitization_version IS NULL OR char_length(btrim(p_sanitization_version)) NOT BETWEEN 1 AND 80 THEN
      RAISE EXCEPTION 'sanitization version is required' USING ERRCODE = '22023';
    END IF;
  ELSIF p_sanitization_version IS NOT NULL THEN
    RAISE EXCEPTION 'sanitization version requires a raw payload' USING ERRCODE = '22023';
  END IF;

  IF btrim(p_subject_ref) <> process_row.cnj_number THEN
    RAISE EXCEPTION 'provider process reference mismatch' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.provider_exchange (
    office_id,
    process_id,
    provider_id,
    source,
    contract_version,
    subject_ref,
    correlation_id,
    request_fingerprint,
    result_kind,
    result_status,
    error_code,
    normalized_result
  ) VALUES (
    actor.actor_office_id,
    p_process_id,
    p_provider_id,
    p_source,
    p_contract_version,
    btrim(p_subject_ref),
    btrim(p_correlation_id),
    btrim(p_request_fingerprint),
    p_result_kind,
    p_result_status,
    nullif(btrim(p_error_code), ''),
    p_normalized_result
  ) ON CONFLICT (office_id, correlation_id) DO NOTHING
  RETURNING id INTO exchange_id;

  IF exchange_id IS NULL THEN
    SELECT * INTO existing_exchange
      FROM public.provider_exchange
     WHERE office_id = actor.actor_office_id
       AND correlation_id = btrim(p_correlation_id)
     FOR SHARE;
    SELECT r.payload_hash INTO existing_payload_hash
      FROM public.raw_provider_payload r
     WHERE r.provider_exchange_id = existing_exchange.id;
    IF existing_exchange.process_id IS DISTINCT FROM p_process_id
       OR existing_exchange.provider_id IS DISTINCT FROM p_provider_id
       OR existing_exchange.source IS DISTINCT FROM p_source
       OR existing_exchange.request_fingerprint IS DISTINCT FROM btrim(p_request_fingerprint)
       OR existing_exchange.result_kind IS DISTINCT FROM p_result_kind
       OR existing_exchange.result_status IS DISTINCT FROM p_result_status
       OR existing_exchange.error_code IS DISTINCT FROM nullif(btrim(p_error_code), '')
       OR existing_exchange.normalized_result IS DISTINCT FROM p_normalized_result
       OR existing_payload_hash IS DISTINCT FROM payload_hash THEN
      RAISE EXCEPTION 'provider correlation replay mismatch' USING ERRCODE = '23505';
    END IF;
    RETURN existing_exchange.id;
  END IF;

  PERFORM public.write_provider_audit(
    'provider.exchange.recorded',
    'provider_exchange',
    exchange_id,
    jsonb_build_object(
      'provider_id', p_provider_id,
      'source', p_source,
      'result_kind', p_result_kind,
      'status', p_result_status,
      'correlation_id', p_correlation_id,
      'error_code', nullif(btrim(p_error_code), '')
    ) - 'error_code'
  );

  IF p_raw_payload IS NOT NULL THEN
    INSERT INTO public.raw_provider_payload (
      provider_exchange_id,
      office_id,
      process_id,
      provider_id,
      source,
      correlation_id,
      sanitization_version,
      payload,
      payload_hash,
      payload_bytes,
      received_at
    ) VALUES (
      exchange_id,
      actor.actor_office_id,
      p_process_id,
      p_provider_id,
      p_source,
      btrim(p_correlation_id),
      btrim(p_sanitization_version),
      p_raw_payload,
      payload_hash,
      payload_bytes,
      coalesce(p_received_at, now())
    ) RETURNING id INTO payload_id;

    PERFORM public.write_provider_audit(
      'provider.payload.recorded',
      'raw_provider_payload',
      payload_id,
      jsonb_build_object(
        'provider_id', p_provider_id,
        'source', p_source,
        'correlation_id', p_correlation_id,
        'payload_hash', payload_hash,
        'payload_bytes', payload_bytes
      )
    );
  END IF;

  RETURN exchange_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_provider_raw_payload(p_exchange_id UUID)
RETURNS TABLE (
  id UUID,
  provider_exchange_id UUID,
  office_id UUID,
  process_id UUID,
  provider_id TEXT,
  source TEXT,
  correlation_id TEXT,
  sanitization_version TEXT,
  payload JSONB,
  payload_hash TEXT,
  payload_bytes INTEGER,
  received_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role <> 'lawyer' THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT r.id, r.provider_exchange_id, r.office_id, r.process_id,
         r.provider_id, r.source, r.correlation_id, r.sanitization_version,
         r.payload, r.payload_hash, r.payload_bytes, r.received_at, r.created_at
    FROM public.raw_provider_payload r
   WHERE r.provider_exchange_id = p_exchange_id
     AND r.office_id = actor.actor_office_id;
END;
$$;

ALTER TABLE public.provider_exchange ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_provider_payload ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.provider_exchange, public.raw_provider_payload FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.provider_exchange TO authenticated;

CREATE POLICY provider_exchange_select_same_office
ON public.provider_exchange
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

REVOKE ALL ON FUNCTION public.provider_json_has_comparison(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.provider_payload_has_sensitive_key(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.provider_payload_integrity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_provider_immutable_mutation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.write_provider_audit(text, text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.require_provider_process_eligible(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_provider_process_eligible(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_provider_exchange(uuid, text, text, integer, text, text, text, text, text, text, jsonb, jsonb, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_provider_raw_payload(uuid) TO authenticated;
