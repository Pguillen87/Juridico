SET lock_timeout = '2s';

-- Fase 12: relatório semanal, revisão e aprovação. Não cria PDF, envio ou sent.

CREATE OR REPLACE FUNCTION public.phase12_hash_version(
  p_schema_version TEXT,
  p_period_start_utc TIMESTAMPTZ,
  p_period_end_utc TIMESTAMPTZ,
  p_structured_content JSONB,
  p_source_manifest JSONB
)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
  SELECT encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'schema_version', p_schema_version,
          'period_start_utc', p_period_start_utc,
          'period_end_utc', p_period_end_utc,
          'structured_content', p_structured_content,
          'source_manifest', p_source_manifest
        )::TEXT,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

CREATE TABLE public.weekly_report (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  client_id UUID NOT NULL,
  report_type TEXT NOT NULL DEFAULT 'weekly' CHECK (report_type = 'weekly'),
  period_start_utc TIMESTAMPTZ NOT NULL,
  period_end_utc TIMESTAMPTZ NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'awaiting_review', 'approved', 'cancelled')),
  current_version_id UUID,
  approved_version_id UUID,
  approved_hash TEXT CHECK (approved_hash IS NULL OR approved_hash ~ '^[0-9a-f]{64}$'),
  approved_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at TIMESTAMPTZ,
  cancelled_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  cancelled_at TIMESTAMPTZ,
  cancel_reason_code TEXT CHECK (
    cancel_reason_code IS NULL OR cancel_reason_code IN (
      'duplicate', 'incorrect_content', 'no_longer_required', 'other'
    )
  ),
  generation_key TEXT NOT NULL CHECK (char_length(btrim(generation_key)) BETWEEN 1 AND 300),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, client_id, period_start_utc, period_end_utc, report_type),
  FOREIGN KEY (office_id, client_id)
    REFERENCES public.client(office_id, id) ON DELETE RESTRICT,
  CHECK (period_start_utc < period_end_utc),
  CHECK ((approved_version_id IS NULL) = (approved_hash IS NULL)),
  CHECK ((approved_version_id IS NULL AND approved_by IS NULL AND approved_at IS NULL)
    OR (approved_version_id IS NOT NULL AND approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK ((cancelled_by IS NULL) = (cancelled_at IS NULL))
);

CREATE TABLE public.report_version (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  report_id UUID NOT NULL,
  version_number INTEGER NOT NULL CHECK (version_number >= 1),
  previous_version_id UUID,
  base_version_id UUID,
  source_version_id UUID,
  created_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  creation_kind TEXT NOT NULL CHECK (creation_kind IN ('generated', 'editorial', 'restored')),
  schema_version TEXT NOT NULL CHECK (schema_version IN ('report-v1')),
  structured_content JSONB NOT NULL CHECK (jsonb_typeof(structured_content) = 'object'),
  source_manifest JSONB NOT NULL CHECK (jsonb_typeof(source_manifest) = 'object'),
  content_hash TEXT NOT NULL CHECK (content_hash ~ '^[0-9a-f]{64}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, report_id, version_number),
  FOREIGN KEY (office_id, report_id)
    REFERENCES public.weekly_report(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, previous_version_id)
    REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, base_version_id)
    REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, source_version_id)
    REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT,
  CHECK ((creation_kind = 'restored' AND source_version_id IS NOT NULL)
    OR (creation_kind <> 'restored' AND source_version_id IS NULL)),
  CHECK (previous_version_id IS NULL OR previous_version_id IS DISTINCT FROM id),
  CHECK (base_version_id IS NULL OR base_version_id IS DISTINCT FROM id),
  CHECK (source_version_id IS NULL OR source_version_id IS DISTINCT FROM id)
);

ALTER TABLE public.weekly_report
  ADD CONSTRAINT weekly_report_current_version_fk
  FOREIGN KEY (office_id, current_version_id)
  REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT;

ALTER TABLE public.weekly_report
  ADD CONSTRAINT weekly_report_approved_version_fk
  FOREIGN KEY (office_id, approved_version_id)
  REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT;

CREATE TABLE public.report_process (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  report_id UUID NOT NULL,
  report_version_id UUID NOT NULL,
  process_id UUID NOT NULL,
  content JSONB NOT NULL CHECK (jsonb_typeof(content) = 'object'),
  source_manifest JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(source_manifest) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, report_version_id, process_id),
  FOREIGN KEY (office_id, report_id)
    REFERENCES public.weekly_report(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, report_version_id)
    REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, process_id)
    REFERENCES public.legal_process(office_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.report_party (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  report_id UUID NOT NULL,
  report_version_id UUID NOT NULL,
  party_id UUID NOT NULL,
  content JSONB NOT NULL CHECK (jsonb_typeof(content) = 'object'),
  source_manifest JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(source_manifest) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, report_version_id, party_id),
  FOREIGN KEY (office_id, report_id)
    REFERENCES public.weekly_report(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, report_version_id)
    REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, party_id)
    REFERENCES public.party(office_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.report_command_idempotency (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  idempotency_key TEXT NOT NULL CHECK (char_length(btrim(idempotency_key)) BETWEEN 1 AND 240),
  operation TEXT NOT NULL CHECK (operation IN (
    'version.create', 'version.restore', 'report.submit', 'report.return',
    'report.approve', 'report.cancel'
  )),
  request_fingerprint TEXT NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  report_id UUID,
  version_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, operation, idempotency_key),
  FOREIGN KEY (office_id, report_id)
    REFERENCES public.weekly_report(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, version_id)
    REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT
);

CREATE INDEX weekly_report_office_status_idx
  ON public.weekly_report (office_id, status, period_end_utc DESC);
CREATE INDEX report_version_report_idx
  ON public.report_version (office_id, report_id, version_number DESC);
CREATE INDEX report_process_report_idx
  ON public.report_process (office_id, report_id, report_version_id);
CREATE INDEX report_party_report_idx
  ON public.report_party (office_id, report_id, report_version_id);
CREATE INDEX report_idempotency_lookup_idx
  ON public.report_command_idempotency (office_id, operation, idempotency_key);

CREATE OR REPLACE FUNCTION public.phase12_block_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase12_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION '% is internal-only and append-only', TG_TABLE_NAME
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION '% is append-only and immutable', TG_TABLE_NAME
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_block_report_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase12_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION '% is writable only through phase 12 domain functions', TG_TABLE_NAME
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '% has no physical deletion', TG_TABLE_NAME USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_block_idempotency_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase12_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'report idempotency is internal-only' USING ERRCODE = '42501';
  END IF;
  IF TG_OP <> 'UPDATE' THEN
    RAISE EXCEPTION 'report idempotency has no physical mutation' USING ERRCODE = '42501';
  END IF;
  IF OLD.office_id IS DISTINCT FROM NEW.office_id
     OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
     OR OLD.operation IS DISTINCT FROM NEW.operation
     OR OLD.request_fingerprint IS DISTINCT FROM NEW.request_fingerprint
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
  THEN
    RAISE EXCEPTION 'report idempotency identity is immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_report_version_append_only
BEFORE UPDATE OR DELETE ON public.report_version
FOR EACH ROW EXECUTE FUNCTION public.phase12_block_version_mutation();

CREATE TRIGGER tr_report_process_append_only
BEFORE UPDATE OR DELETE ON public.report_process
FOR EACH ROW EXECUTE FUNCTION public.phase12_block_version_mutation();

CREATE TRIGGER tr_report_party_append_only
BEFORE UPDATE OR DELETE ON public.report_party
FOR EACH ROW EXECUTE FUNCTION public.phase12_block_version_mutation();

CREATE TRIGGER tr_weekly_report_domain_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.weekly_report
FOR EACH ROW EXECUTE FUNCTION public.phase12_block_report_mutation();

CREATE TRIGGER tr_report_idempotency_guard
BEFORE UPDATE OR DELETE ON public.report_command_idempotency
FOR EACH ROW EXECUTE FUNCTION public.phase12_block_idempotency_mutation();

CREATE OR REPLACE FUNCTION public.phase12_can_view_report_row(p_office_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.user_profile up
      JOIN public.office o ON o.id = up.office_id
     WHERE up.id = auth.uid()
       AND up.office_id = p_office_id
       AND up.is_active = true
       AND o.is_active = true
       AND up.role IN ('lawyer', 'reviewer')
  );
$$;

CREATE OR REPLACE FUNCTION public.phase12_write_audit_internal(
  p_action TEXT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_office_id UUID,
  p_actor_user_id UUID,
  p_metadata JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  audit_id BIGINT;
  metadata_key TEXT;
  actor RECORD;
BEGIN
  IF current_setting('juridico.phase12_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'phase 12 audit writer is internal-only' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN (
    'weekly_report.generated', 'report_version.created',
    'weekly_report.submitted_for_review', 'weekly_report.returned_to_draft',
    'weekly_report.approved', 'weekly_report.cancelled'
  ) THEN
    RAISE EXCEPTION 'phase 12 audit action is not allowlisted' USING ERRCODE = '22023';
  END IF;
  IF p_entity_type NOT IN ('weekly_report', 'report_version')
     OR p_office_id IS NULL
     OR p_metadata IS NULL
     OR jsonb_typeof(p_metadata) <> 'object'
  THEN
    RAISE EXCEPTION 'invalid phase 12 audit input' USING ERRCODE = '22023';
  END IF;
  IF p_actor_user_id IS NOT NULL THEN
    SELECT * INTO actor FROM public.require_active_actor();
    IF actor.actor_id IS DISTINCT FROM p_actor_user_id
       OR actor.actor_office_id IS DISTINCT FROM p_office_id
    THEN
      RAISE EXCEPTION 'phase 12 audit actor mismatch' USING ERRCODE = '42501';
    END IF;
  ELSIF current_user NOT IN ('postgres', 'service_role') THEN
    RAISE EXCEPTION 'phase 12 system audit is backend-only' USING ERRCODE = '42501';
  END IF;
  FOR metadata_key IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF metadata_key NOT IN (
      'period_start_utc', 'period_end_utc', 'status', 'before_status', 'after_status',
      'version_number', 'previous_version_id', 'base_version_id', 'source_version_id',
      'content_hash', 'approved_hash', 'reason_code', 'result', 'idempotency_key',
      'correlation_id', 'generation_key'
    ) THEN
      RAISE EXCEPTION 'phase 12 audit metadata key is not allowlisted' USING ERRCODE = '22023';
    END IF;
  END LOOP;
  INSERT INTO public.audit_log (
    audit_scope, office_id, actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    'operational', p_office_id, p_actor_user_id, p_action, p_entity_type, p_entity_id, p_metadata
  ) RETURNING id INTO audit_id;
  RETURN audit_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_validate_editorial(p_editorial JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  field_name TEXT;
  field_value JSONB;
  nested_key TEXT;
  nested_value JSONB;
  max_text_length INTEGER;
BEGIN
  IF p_editorial IS NULL OR jsonb_typeof(p_editorial) <> 'object' THEN
    RAISE EXCEPTION 'invalid editorial content' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(p_editorial)) < 1
     OR (SELECT count(*) FROM jsonb_object_keys(p_editorial)) > 5
  THEN
    RAISE EXCEPTION 'invalid editorial content' USING ERRCODE = '22023';
  END IF;
  FOR field_name, field_value IN SELECT key, value FROM jsonb_each(p_editorial) LOOP
    IF field_name NOT IN ('title', 'summary_note', 'process_notes', 'party_notes', 'closing_note') THEN
      RAISE EXCEPTION 'editorial field is not allowlisted' USING ERRCODE = '22023';
    END IF;
    IF field_name IN ('title', 'summary_note', 'closing_note') THEN
      max_text_length := CASE WHEN field_name = 'title' THEN 240 ELSE 2000 END;
      IF jsonb_typeof(field_value) <> 'string'
         OR char_length(btrim(field_value #>> '{}')) < 1
         OR char_length(field_value #>> '{}') > max_text_length
      THEN
        RAISE EXCEPTION 'invalid editorial text' USING ERRCODE = '22023';
      END IF;
    ELSE
      IF jsonb_typeof(field_value) <> 'object' THEN
        RAISE EXCEPTION 'invalid editorial notes' USING ERRCODE = '22023';
      END IF;
      IF (SELECT count(*) FROM jsonb_object_keys(field_value)) > 200 THEN
        RAISE EXCEPTION 'invalid editorial notes' USING ERRCODE = '22023';
      END IF;
      FOR nested_key, nested_value IN
        SELECT key, value FROM jsonb_each(field_value)
      LOOP
        IF nested_key !~ '^[0-9a-fA-F-]{36}$'
           OR jsonb_typeof(nested_value) <> 'string'
           OR char_length(btrim(nested_value #>> '{}')) < 1
           OR char_length(nested_value #>> '{}') > 1000
        THEN
          RAISE EXCEPTION 'invalid editorial note' USING ERRCODE = '22023';
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_assert_backend()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_user NOT IN ('postgres', 'service_role') THEN
    RAISE EXCEPTION 'phase 12 generation is backend-only' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_period_end_for(p_as_of_utc TIMESTAMPTZ)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  local_as_of TIMESTAMP;
  local_end TIMESTAMP;
  day_offset INTEGER;
BEGIN
  IF p_as_of_utc IS NULL THEN
    RAISE EXCEPTION 'as_of is required' USING ERRCODE = '22023';
  END IF;
  local_as_of := p_as_of_utc AT TIME ZONE 'America/Sao_Paulo';
  day_offset := (EXTRACT(DOW FROM local_as_of)::INTEGER - 5 + 7) % 7;
  local_end := date_trunc('day', local_as_of) + INTERVAL '17 hours' - (day_offset * INTERVAL '1 day');
  IF local_end > local_as_of THEN
    local_end := local_end - INTERVAL '7 days';
  END IF;
  RETURN local_end AT TIME ZONE 'America/Sao_Paulo';
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_period_start_for(p_period_end_utc TIMESTAMPTZ)
RETURNS TIMESTAMPTZ
LANGUAGE SQL
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
  SELECT ((p_period_end_utc AT TIME ZONE 'America/Sao_Paulo') - INTERVAL '7 days')
    AT TIME ZONE 'America/Sao_Paulo';
$$;

CREATE OR REPLACE FUNCTION public.phase12_process_history_proven(
  p_office_id UUID,
  p_client_id UUID,
  p_process_id UUID,
  p_period_end_utc TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.legal_process lp
      JOIN public.audit_log al
        ON al.office_id = lp.office_id
       AND al.entity_type = 'legal_process'
       AND al.entity_id = lp.id
       AND al.action IN ('process.created', 'process.imported')
     WHERE lp.office_id = p_office_id
       AND lp.id = p_process_id
       AND lp.client_id = p_client_id
       AND lp.created_at < p_period_end_utc
       AND al.created_at < p_period_end_utc
       AND (al.metadata #>> '{after,client_id}') = p_client_id::TEXT
  );
$$;

CREATE OR REPLACE FUNCTION public.phase12_process_party_history_proven(
  p_office_id UUID,
  p_relation_id UUID,
  p_period_end_utc TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.process_party pp
      JOIN public.audit_log al
        ON al.office_id = pp.office_id
       AND al.entity_id = pp.id
       AND al.entity_type = 'process_party'
       AND al.action IN ('process_party.created', 'process_party.confirmed', 'process_party.rejected')
     WHERE pp.office_id = p_office_id
       AND pp.id = p_relation_id
       AND pp.created_at < p_period_end_utc
       AND al.created_at < p_period_end_utc
  );
$$;

CREATE OR REPLACE FUNCTION public.phase12_build_source_manifest(
  p_office_id UUID,
  p_client_id UUID,
  p_period_start_utc TIMESTAMPTZ,
  p_period_end_utc TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_build_object(
    'cutoff_utc', p_period_end_utc,
    'period_start_utc', p_period_start_utc,
    'period_end_utc', p_period_end_utc,
    'sources', COALESCE((
      SELECT jsonb_agg(source_row ORDER BY source_type, source_id)
        FROM (
          SELECT 'comparison'::TEXT AS source_type, pc.id::TEXT AS source_id, pc.created_at AS occurred_at
            FROM public.process_comparison pc
            JOIN public.legal_process lp ON lp.office_id = pc.office_id AND lp.id = pc.process_id
           WHERE pc.office_id = p_office_id AND lp.client_id = p_client_id
             AND pc.created_at >= p_period_start_utc AND pc.created_at < p_period_end_utc
          UNION ALL
          SELECT 'detected_change', dc.id::TEXT, dc.detected_at
            FROM public.detected_change dc
            JOIN public.legal_process lp ON lp.office_id = dc.office_id AND lp.id = dc.process_id
           WHERE dc.office_id = p_office_id AND lp.client_id = p_client_id
             AND dc.detected_at >= p_period_start_utc AND dc.detected_at < p_period_end_utc
          UNION ALL
          SELECT 'failure_occurrence', fo.id::TEXT, fo.occurred_at
            FROM public.failure_occurrence fo
            JOIN public.legal_process lp ON lp.office_id = fo.office_id AND lp.id = fo.process_id
           WHERE fo.office_id = p_office_id AND lp.client_id = p_client_id
             AND fo.occurred_at >= p_period_start_utc AND fo.occurred_at < p_period_end_utc
             AND fo.event_kind = 'failure_observed'
          UNION ALL
          SELECT 'query_execution', qe.id::TEXT, COALESCE(qe.finished_at, qe.started_at)
            FROM public.query_execution qe
            JOIN public.legal_process lp ON lp.office_id = qe.office_id AND lp.id = qe.process_id
           WHERE qe.office_id = p_office_id AND lp.client_id = p_client_id
             AND COALESCE(qe.finished_at, qe.started_at) >= p_period_start_utc
             AND COALESCE(qe.finished_at, qe.started_at) < p_period_end_utc
          UNION ALL
          SELECT 'snapshot', ps.id::TEXT, ps.created_at
            FROM public.process_snapshot ps
            JOIN public.legal_process lp ON lp.office_id = ps.office_id AND lp.id = ps.process_id
           WHERE ps.office_id = p_office_id AND lp.client_id = p_client_id
             AND ps.created_at >= p_period_start_utc AND ps.created_at < p_period_end_utc
        ) source_row
    ), '[]'::jsonb)
  );
$$;

CREATE OR REPLACE FUNCTION public.phase12_build_report_content(
  p_office_id UUID,
  p_client_id UUID,
  p_period_start_utc TIMESTAMPTZ,
  p_period_end_utc TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  process_content JSONB;
  party_content JSONB;
  process_row RECORD;
  party_row RECORD;
BEGIN
  IF EXISTS (
    SELECT 1
      FROM public.legal_process lp
     WHERE lp.office_id = p_office_id
       AND lp.client_id = p_client_id
       AND lp.created_at < p_period_end_utc
       AND NOT public.phase12_process_history_proven(
         p_office_id, p_client_id, lp.id, p_period_end_utc
       )
  ) THEN
    RAISE EXCEPTION 'manual_review_required' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'process_id', lp.id,
      'cnj_number', lp.cnj_number,
      'tribunal', lp.tribunal,
      'last_valid_query_at', (
        SELECT max(COALESCE(qe.finished_at, qe.started_at))
          FROM public.query_execution qe
         WHERE qe.office_id = lp.office_id
           AND qe.process_id = lp.id
           AND qe.status = 'succeeded'
           AND COALESCE(qe.finished_at, qe.started_at) < p_period_end_utc
      ),
      'changed', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'comparison_id', pc.id,
          'changed_fields', pc.changed_fields,
          'normalized_diff', pc.normalized_diff,
          'comparison_hash', pc.comparison_hash,
          'detected_change_id', (
            SELECT dc.id
              FROM public.detected_change dc
             WHERE dc.office_id = pc.office_id
               AND dc.process_id = pc.process_id
               AND dc.comparison_id = pc.id
             ORDER BY dc.detected_at, dc.id
             LIMIT 1
          ),
          'occurred_at', pc.created_at
        ) ORDER BY pc.created_at, pc.id)
          FROM public.process_comparison pc
         WHERE pc.office_id = lp.office_id
           AND pc.process_id = lp.id
           AND pc.result = 'changed'
           AND pc.created_at >= p_period_start_utc
           AND pc.created_at < p_period_end_utc
      ), '[]'::jsonb),
      'unchanged', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'comparison_id', pc.id,
          'comparison_hash', pc.comparison_hash,
          'occurred_at', pc.created_at
        ) ORDER BY pc.created_at, pc.id)
          FROM public.process_comparison pc
         WHERE pc.office_id = lp.office_id
           AND pc.process_id = lp.id
           AND pc.result = 'unchanged'
           AND pc.created_at >= p_period_start_utc
           AND pc.created_at < p_period_end_utc
      ), '[]'::jsonb),
      'not_comparable', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'comparison_id', pc.id,
          'reason_code', pc.reason_code,
          'occurred_at', pc.created_at
        ) ORDER BY pc.created_at, pc.id)
          FROM public.process_comparison pc
         WHERE pc.office_id = lp.office_id
           AND pc.process_id = lp.id
           AND pc.result = 'not_comparable'
           AND pc.created_at >= p_period_start_utc
           AND pc.created_at < p_period_end_utc
      ), '[]'::jsonb),
      'failures', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'occurrence_id', fo.id,
          'incident_id', fo.incident_id,
          'failure_code', fo.failure_code,
          'failure_class', fo.failure_class,
          'source_type', fo.source_type,
          'source_id', fo.source_id,
          'attempt_number', fo.attempt_number,
          'sanitized_message_code', fo.sanitized_message_code,
          'occurred_at', fo.occurred_at
        ) ORDER BY fo.occurred_at, fo.id)
          FROM public.failure_occurrence fo
         WHERE fo.office_id = lp.office_id
           AND fo.process_id = lp.id
           AND fo.event_kind = 'failure_observed'
           AND fo.occurred_at >= p_period_start_utc
           AND fo.occurred_at < p_period_end_utc
      ), '[]'::jsonb),
      'manual_review_required', EXISTS (
        SELECT 1
          FROM public.process_party pp
         WHERE pp.office_id = lp.office_id
           AND pp.process_id = lp.id
           AND pp.created_at < p_period_end_utc
           AND NOT EXISTS (
             SELECT 1
               FROM public.audit_log al_deactivated
              WHERE al_deactivated.office_id = pp.office_id
                AND al_deactivated.entity_type = 'process_party'
                AND al_deactivated.entity_id = pp.id
                AND al_deactivated.action = 'process_party.deactivated'
                AND al_deactivated.created_at < p_period_end_utc
           )
           AND (
             NOT public.phase12_process_party_history_proven(
               pp.office_id, pp.id, p_period_end_utc
             )
             OR NOT EXISTS (
               SELECT 1
                 FROM public.audit_log al_confirm
                WHERE al_confirm.office_id = pp.office_id
                  AND al_confirm.entity_type = 'process_party'
                  AND al_confirm.entity_id = pp.id
                  AND al_confirm.action = 'process_party.confirmed'
                  AND al_confirm.created_at < p_period_end_utc
             )
           )
      )
    ) ORDER BY lp.id
  ), '[]'::jsonb)
    INTO process_content
    FROM public.legal_process lp
   WHERE lp.office_id = p_office_id
     AND lp.client_id = p_client_id
     AND lp.created_at < p_period_end_utc;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'party_id', p.id,
      'party_type', p.party_type,
      'display_name', p.display_name,
      'relationship_state', relationship_state,
      'process_ids', process_ids,
      'manual_review_required', manual_review_required
    ) ORDER BY p.id
  ), '[]'::jsonb)
    INTO party_content
    FROM public.party p
    JOIN LATERAL (
      SELECT
        CASE
          WHEN bool_or(COALESCE(history.confirmation_status, 'pending') = 'confirmed') THEN 'confirmed'
          WHEN bool_or(COALESCE(history.confirmation_status, 'pending') = 'pending') THEN 'pending'
          ELSE 'rejected'
        END AS relationship_state,
        jsonb_agg(DISTINCT pp.process_id ORDER BY pp.process_id) AS process_ids,
        bool_or(
          COALESCE(history.confirmation_status, 'pending') <> 'confirmed'
          OR history.has_history IS DISTINCT FROM true
        ) AS manual_review_required
      FROM public.process_party pp
      JOIN public.legal_process lp_party
        ON lp_party.office_id = pp.office_id
       AND lp_party.id = pp.process_id
       AND lp_party.client_id = p_client_id
      LEFT JOIN LATERAL (
        SELECT
          COALESCE(al.metadata #>> '{after,confirmation_status}', 'pending') AS confirmation_status,
          true AS has_history
          FROM public.audit_log al
         WHERE al.office_id = pp.office_id
           AND al.entity_type = 'process_party'
           AND al.entity_id = pp.id
           AND al.action IN (
             'process_party.created', 'process_party.confirmed', 'process_party.rejected'
           )
           AND al.created_at < p_period_end_utc
         ORDER BY al.created_at DESC, al.id DESC
         LIMIT 1
      ) history ON true
      WHERE pp.office_id = p_office_id
        AND pp.party_id = p.id
        AND pp.created_at < p_period_end_utc
        AND NOT EXISTS (
          SELECT 1
            FROM public.audit_log al_deactivated
           WHERE al_deactivated.office_id = pp.office_id
             AND al_deactivated.entity_type = 'process_party'
             AND al_deactivated.entity_id = pp.id
             AND al_deactivated.action = 'process_party.deactivated'
             AND al_deactivated.created_at < p_period_end_utc
        )
    ) rel ON rel.process_ids IS NOT NULL
   WHERE p.office_id = p_office_id
     AND EXISTS (
       SELECT 1
         FROM public.process_party pp2
         JOIN public.legal_process lp2
           ON lp2.office_id = pp2.office_id
          AND lp2.id = pp2.process_id
        WHERE pp2.office_id = p_office_id
          AND pp2.party_id = p.id
          AND lp2.client_id = p_client_id
          AND pp2.created_at < p_period_end_utc
          AND NOT EXISTS (
            SELECT 1
              FROM public.audit_log al2_deactivated
             WHERE al2_deactivated.office_id = pp2.office_id
               AND al2_deactivated.entity_type = 'process_party'
               AND al2_deactivated.entity_id = pp2.id
               AND al2_deactivated.action = 'process_party.deactivated'
               AND al2_deactivated.created_at < p_period_end_utc
          )
     );

  RETURN jsonb_build_object(
    'schema_version', 'report-v1',
    'period_start_utc', p_period_start_utc,
    'period_end_utc', p_period_end_utc,
    'processes', process_content,
    'parties', party_content,
    'empty_explanation', CASE
      WHEN jsonb_array_length(process_content) = 0
       AND jsonb_array_length(party_content) = 0
      THEN 'Nenhuma evidência elegível no período.'
      ELSE NULL
    END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_generate_weekly_report(
  p_office_id UUID,
  p_client_id UUID,
  p_period_start_utc TIMESTAMPTZ DEFAULT NULL,
  p_period_end_utc TIMESTAMPTZ DEFAULT NULL,
  p_as_of_utc TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE(report_id UUID, version_id UUID, replayed BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  period_start_value TIMESTAMPTZ;
  period_end_value TIMESTAMPTZ;
  report_row public.weekly_report%ROWTYPE;
  content_value JSONB;
  manifest_value JSONB;
  version_hash TEXT;
  new_report_id UUID;
  new_version_id UUID;
  generation_key_value TEXT;
  audit_id BIGINT;
  process_row RECORD;
  party_row RECORD;
BEGIN
  PERFORM public.phase12_assert_backend();
  IF p_office_id IS NULL OR p_client_id IS NULL OR p_as_of_utc IS NULL THEN
    RAISE EXCEPTION 'invalid phase 12 generation input' USING ERRCODE = '22023';
  END IF;
  SELECT period_end_utc INTO period_end_value
    FROM (SELECT COALESCE(p_period_end_utc, public.phase12_period_end_for(p_as_of_utc)) AS period_end_utc) value;
  period_start_value := COALESCE(p_period_start_utc, public.phase12_period_start_for(period_end_value));
  IF period_start_value >= period_end_value
     OR public.phase12_period_start_for(period_end_value) IS DISTINCT FROM period_start_value
     OR public.phase12_period_end_for(period_end_value + INTERVAL '1 minute') IS DISTINCT FROM period_end_value
  THEN
    RAISE EXCEPTION 'invalid report period' USING ERRCODE = '22023';
  END IF;
  IF period_end_value > p_as_of_utc THEN
    RAISE EXCEPTION 'report period is not closed' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.office o
     WHERE o.id = p_office_id AND o.is_active = true
  ) OR NOT EXISTS (
    SELECT 1 FROM public.client c
     WHERE c.office_id = p_office_id AND c.id = p_client_id
  ) THEN
    RAISE EXCEPTION 'report client not found' USING ERRCODE = 'P0002';
  END IF;

  generation_key_value := format(
    'weekly:%s:%s:%s:%s', p_office_id, p_client_id, period_start_value, period_end_value
  );
  PERFORM set_config('juridico.phase12_internal', '1', true);
  content_value := public.phase12_build_report_content(
    p_office_id, p_client_id, period_start_value, period_end_value
  );
  manifest_value := public.phase12_build_source_manifest(
    p_office_id, p_client_id, period_start_value, period_end_value
  );
  version_hash := public.phase12_hash_version(
    'report-v1', period_start_value, period_end_value, content_value, manifest_value
  );

  INSERT INTO public.weekly_report (
    office_id, client_id, period_start_utc, period_end_utc, timezone,
    status, generation_key
  ) VALUES (
    p_office_id, p_client_id, period_start_value, period_end_value, 'America/Sao_Paulo',
    'draft', generation_key_value
  ) ON CONFLICT (office_id, client_id, period_start_utc, period_end_utc, report_type)
    DO NOTHING
    RETURNING id INTO new_report_id;

  IF new_report_id IS NULL THEN
    SELECT * INTO report_row
      FROM public.weekly_report
     WHERE office_id = p_office_id
       AND client_id = p_client_id
       AND period_start_utc = period_start_value
       AND period_end_utc = period_end_value
       AND report_type = 'weekly'
     FOR UPDATE;
    report_id := report_row.id;
    version_id := report_row.current_version_id;
    replayed := true;
    RETURN NEXT;
    RETURN;
  END IF;

  INSERT INTO public.report_version (
    office_id, report_id, version_number, previous_version_id, base_version_id,
    created_by, creation_kind, schema_version, structured_content, source_manifest, content_hash
  ) VALUES (
    p_office_id, new_report_id, 1, NULL, NULL, NULL, 'generated', 'report-v1',
    content_value, manifest_value, version_hash
  ) RETURNING id INTO new_version_id;

  UPDATE public.weekly_report
     SET current_version_id = new_version_id, updated_at = clock_timestamp()
   WHERE office_id = p_office_id AND id = new_report_id;

  FOR process_row IN
    SELECT value ->> 'process_id' AS process_id, value AS content
      FROM jsonb_array_elements(content_value -> 'processes')
  LOOP
    INSERT INTO public.report_process (
      office_id, report_id, report_version_id, process_id, content, source_manifest
    ) VALUES (
      p_office_id, new_report_id, new_version_id, process_row.process_id::UUID,
      process_row.content, jsonb_build_object('cutoff_utc', period_end_value)
    );
  END LOOP;

  FOR party_row IN
    SELECT value ->> 'party_id' AS party_id, value AS content
      FROM jsonb_array_elements(content_value -> 'parties')
  LOOP
    INSERT INTO public.report_party (
      office_id, report_id, report_version_id, party_id, content, source_manifest
    ) VALUES (
      p_office_id, new_report_id, new_version_id, party_row.party_id::UUID,
      party_row.content, jsonb_build_object('cutoff_utc', period_end_value)
    );
  END LOOP;

  audit_id := public.phase12_write_audit_internal(
    'weekly_report.generated', 'weekly_report', new_report_id, p_office_id, NULL,
    jsonb_build_object(
      'period_start_utc', period_start_value,
      'period_end_utc', period_end_value,
      'status', 'draft',
      'version_number', 1,
      'content_hash', version_hash,
      'generation_key', generation_key_value,
      'result', 'created',
      'correlation_id', gen_random_uuid()
    )
  );
  audit_id := public.phase12_write_audit_internal(
    'report_version.created', 'report_version', new_version_id, p_office_id, NULL,
    jsonb_build_object(
      'version_number', 1, 'content_hash', version_hash, 'result', 'created',
      'correlation_id', gen_random_uuid()
    )
  );
  report_id := new_report_id;
  version_id := new_version_id;
  replayed := false;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_register_command(
  p_office_id UUID,
  p_operation TEXT,
  p_idempotency_key TEXT,
  p_request_fingerprint TEXT,
  p_report_id UUID,
  OUT existing_report_id UUID,
  OUT existing_version_id UUID,
  OUT is_replay BOOLEAN
)
RETURNS RECORD
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  existing public.report_command_idempotency%ROWTYPE;
  inserted_count INTEGER;
BEGIN
  IF current_setting('juridico.phase12_internal', true) IS DISTINCT FROM '1'
     OR p_office_id IS NULL
     OR p_operation NOT IN (
       'version.create', 'version.restore', 'report.submit', 'report.return',
       'report.approve', 'report.cancel'
     )
     OR p_idempotency_key IS NULL
     OR p_request_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'invalid phase 12 idempotency input' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.report_command_idempotency (
    office_id, operation, idempotency_key, request_fingerprint, report_id
  ) VALUES (
    p_office_id, p_operation, p_idempotency_key, p_request_fingerprint, p_report_id
  ) ON CONFLICT (office_id, operation, idempotency_key) DO NOTHING;
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  SELECT * INTO existing
    FROM public.report_command_idempotency
   WHERE office_id = p_office_id
     AND operation = p_operation
     AND idempotency_key = p_idempotency_key
   FOR UPDATE;
  IF existing.request_fingerprint IS DISTINCT FROM p_request_fingerprint THEN
    RAISE EXCEPTION 'idempotency key reused with different request' USING ERRCODE = '23505';
  END IF;
  existing_report_id := existing.report_id;
  existing_version_id := existing.version_id;
  is_replay := inserted_count = 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_complete_command(
  p_office_id UUID,
  p_operation TEXT,
  p_idempotency_key TEXT,
  p_report_id UUID,
  p_version_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_setting('juridico.phase12_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'phase 12 idempotency completion is internal-only' USING ERRCODE = '42501';
  END IF;
  UPDATE public.report_command_idempotency
     SET report_id = p_report_id, version_id = p_version_id
   WHERE office_id = p_office_id AND operation = p_operation AND idempotency_key = p_idempotency_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'idempotency command was not registered' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_create_editorial_version(
  p_report_id UUID,
  p_base_version_id UUID,
  p_editorial JSONB,
  p_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  report_row public.weekly_report%ROWTYPE;
  base_version public.report_version%ROWTYPE;
  new_version UUID;
  new_number INTEGER;
  fingerprint TEXT;
  old_report_id UUID;
  old_version_id UUID;
  replay BOOLEAN;
  content_value JSONB;
  manifest_value JSONB;
  content_hash_value TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'reviewer') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  PERFORM public.phase12_validate_editorial(p_editorial);
  PERFORM set_config('juridico.phase12_internal', '1', true);
  fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object('report_id', p_report_id, 'base_version_id', p_base_version_id, 'editorial', p_editorial)::TEXT,
    'UTF8'), 'sha256'), 'hex');
  SELECT * INTO old_report_id, old_version_id, replay
    FROM public.phase12_register_command(
      actor.actor_office_id, 'version.create', p_idempotency_key, fingerprint, p_report_id
    );
  IF replay AND old_version_id IS NOT NULL THEN
    RETURN old_version_id;
  END IF;
  SELECT * INTO report_row FROM public.weekly_report
   WHERE office_id = actor.actor_office_id AND id = p_report_id FOR UPDATE;
  IF report_row.id IS NULL OR report_row.status NOT IN ('draft', 'awaiting_review') THEN
    RAISE EXCEPTION 'report is not editable' USING ERRCODE = 'P0001';
  END IF;
  SELECT * INTO base_version FROM public.report_version
   WHERE office_id = actor.actor_office_id AND id = p_base_version_id AND report_id = report_row.id;
  IF base_version.id IS NULL OR report_row.current_version_id IS DISTINCT FROM base_version.id THEN
    RAISE EXCEPTION 'stale report version' USING ERRCODE = '40001';
  END IF;
  content_value := base_version.structured_content || jsonb_build_object('editorial', p_editorial);
  manifest_value := base_version.source_manifest;
  content_hash_value := public.phase12_hash_version(
    base_version.schema_version, report_row.period_start_utc, report_row.period_end_utc,
    content_value, manifest_value
  );
  SELECT COALESCE(max(version_number), 0) + 1 INTO new_number
    FROM public.report_version WHERE office_id = actor.actor_office_id AND report_id = report_row.id;
  INSERT INTO public.report_version (
    office_id, report_id, version_number, previous_version_id, base_version_id,
    created_by, creation_kind, schema_version, structured_content, source_manifest, content_hash
  ) VALUES (
    actor.actor_office_id, report_row.id, new_number, base_version.id, base_version.id,
    actor.actor_id, 'editorial', base_version.schema_version, content_value, manifest_value, content_hash_value
  ) RETURNING id INTO new_version;
  UPDATE public.weekly_report SET current_version_id = new_version, updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = report_row.id;
  PERFORM public.phase12_write_audit_internal(
    'report_version.created', 'report_version', new_version, actor.actor_office_id, actor.actor_id,
    jsonb_build_object('version_number', new_number, 'previous_version_id', base_version.id,
                       'base_version_id', base_version.id, 'content_hash', content_hash_value,
                       'result', 'created', 'idempotency_key', p_idempotency_key,
                       'correlation_id', gen_random_uuid())
  );
  PERFORM public.phase12_complete_command(
    actor.actor_office_id, 'version.create', p_idempotency_key, report_row.id, new_version
  );
  RETURN new_version;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_restore_report_version(
  p_report_id UUID,
  p_base_version_id UUID,
  p_source_version_id UUID,
  p_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  report_row public.weekly_report%ROWTYPE;
  base_version public.report_version%ROWTYPE;
  source_version public.report_version%ROWTYPE;
  new_version UUID;
  new_number INTEGER;
  fingerprint TEXT;
  old_report_id UUID;
  old_version_id UUID;
  replay BOOLEAN;
  content_value JSONB;
  content_hash_value TEXT;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'reviewer') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('juridico.phase12_internal', '1', true);
  fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object('report_id', p_report_id, 'base_version_id', p_base_version_id,
                       'source_version_id', p_source_version_id)::TEXT, 'UTF8'), 'sha256'), 'hex');
  SELECT * INTO old_report_id, old_version_id, replay
    FROM public.phase12_register_command(
      actor.actor_office_id, 'version.restore', p_idempotency_key, fingerprint, p_report_id
    );
  IF replay AND old_version_id IS NOT NULL THEN
    RETURN old_version_id;
  END IF;
  SELECT * INTO report_row FROM public.weekly_report
   WHERE office_id = actor.actor_office_id AND id = p_report_id FOR UPDATE;
  IF report_row.id IS NULL OR report_row.status NOT IN ('draft', 'awaiting_review') THEN
    RAISE EXCEPTION 'report is not restorable' USING ERRCODE = 'P0001';
  END IF;
  SELECT * INTO base_version FROM public.report_version
   WHERE office_id = actor.actor_office_id AND id = p_base_version_id AND report_id = report_row.id;
  SELECT * INTO source_version FROM public.report_version
   WHERE office_id = actor.actor_office_id AND id = p_source_version_id AND report_id = report_row.id;
  IF base_version.id IS NULL OR report_row.current_version_id IS DISTINCT FROM base_version.id THEN
    RAISE EXCEPTION 'stale report version' USING ERRCODE = '40001';
  END IF;
  IF source_version.id IS NULL THEN
    RAISE EXCEPTION 'source report version not found' USING ERRCODE = 'P0002';
  END IF;
  content_value := base_version.structured_content || jsonb_build_object(
    'editorial', COALESCE(source_version.structured_content -> 'editorial', '{}'::jsonb)
  );
  content_hash_value := public.phase12_hash_version(
    base_version.schema_version, report_row.period_start_utc, report_row.period_end_utc,
    content_value, base_version.source_manifest
  );
  SELECT COALESCE(max(version_number), 0) + 1 INTO new_number
    FROM public.report_version WHERE office_id = actor.actor_office_id AND report_id = report_row.id;
  INSERT INTO public.report_version (
    office_id, report_id, version_number, previous_version_id, base_version_id, source_version_id,
    created_by, creation_kind, schema_version, structured_content, source_manifest, content_hash
  ) VALUES (
    actor.actor_office_id, report_row.id, new_number, base_version.id, base_version.id, source_version.id,
    actor.actor_id, 'restored', base_version.schema_version, content_value, base_version.source_manifest, content_hash_value
  ) RETURNING id INTO new_version;
  UPDATE public.weekly_report SET current_version_id = new_version, updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = report_row.id;
  PERFORM public.phase12_write_audit_internal(
    'report_version.created', 'report_version', new_version, actor.actor_office_id, actor.actor_id,
    jsonb_build_object('version_number', new_number, 'previous_version_id', base_version.id,
                       'base_version_id', base_version.id, 'source_version_id', source_version.id,
                       'content_hash', content_hash_value, 'result', 'restored',
                       'idempotency_key', p_idempotency_key, 'correlation_id', gen_random_uuid())
  );
  PERFORM public.phase12_complete_command(
    actor.actor_office_id, 'version.restore', p_idempotency_key, report_row.id, new_version
  );
  RETURN new_version;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_submit_report(
  p_report_id UUID,
  p_version_id UUID,
  p_idempotency_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  report_row public.weekly_report%ROWTYPE;
  version_row public.report_version%ROWTYPE;
  fingerprint TEXT;
  old_report_id UUID;
  old_version_id UUID;
  replay BOOLEAN;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'reviewer') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('juridico.phase12_internal', '1', true);
  fingerprint := encode(extensions.digest(convert_to(jsonb_build_object('report_id', p_report_id, 'version_id', p_version_id)::TEXT, 'UTF8'), 'sha256'), 'hex');
  SELECT * INTO old_report_id, old_version_id, replay FROM public.phase12_register_command(actor.actor_office_id, 'report.submit', p_idempotency_key, fingerprint, p_report_id);
  IF replay THEN RETURN; END IF;
  SELECT * INTO report_row FROM public.weekly_report
   WHERE office_id = actor.actor_office_id AND id = p_report_id FOR UPDATE;
  SELECT * INTO version_row FROM public.report_version
   WHERE office_id = actor.actor_office_id AND id = p_version_id AND report_id = p_report_id;
  IF report_row.id IS NULL OR version_row.id IS NULL OR report_row.current_version_id IS DISTINCT FROM p_version_id
     OR report_row.status <> 'draft' THEN
    RAISE EXCEPTION 'invalid report submission' USING ERRCODE = 'P0001';
  END IF;
  UPDATE public.weekly_report SET status = 'awaiting_review', updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = p_report_id;
  PERFORM public.phase12_write_audit_internal(
    'weekly_report.submitted_for_review', 'weekly_report', p_report_id, actor.actor_office_id, actor.actor_id,
    jsonb_build_object('before_status', 'draft', 'after_status', 'awaiting_review', 'version_number', version_row.version_number,
                       'content_hash', version_row.content_hash, 'result', 'submitted', 'idempotency_key', p_idempotency_key,
                       'correlation_id', gen_random_uuid())
  );
  PERFORM public.phase12_complete_command(actor.actor_office_id, 'report.submit', p_idempotency_key, p_report_id, p_version_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_return_report_to_draft(
  p_report_id UUID,
  p_version_id UUID,
  p_idempotency_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  report_row public.weekly_report%ROWTYPE;
  version_row public.report_version%ROWTYPE;
  fingerprint TEXT;
  old_report_id UUID;
  old_version_id UUID;
  replay BOOLEAN;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'reviewer') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('juridico.phase12_internal', '1', true);
  fingerprint := encode(extensions.digest(convert_to(jsonb_build_object('report_id', p_report_id, 'version_id', p_version_id)::TEXT, 'UTF8'), 'sha256'), 'hex');
  SELECT * INTO old_report_id, old_version_id, replay FROM public.phase12_register_command(actor.actor_office_id, 'report.return', p_idempotency_key, fingerprint, p_report_id);
  IF replay THEN RETURN; END IF;
  SELECT * INTO report_row FROM public.weekly_report WHERE office_id = actor.actor_office_id AND id = p_report_id FOR UPDATE;
  SELECT * INTO version_row FROM public.report_version WHERE office_id = actor.actor_office_id AND id = p_version_id AND report_id = p_report_id;
  IF report_row.id IS NULL OR version_row.id IS NULL OR report_row.current_version_id IS DISTINCT FROM p_version_id OR report_row.status <> 'awaiting_review' THEN
    RAISE EXCEPTION 'invalid report return' USING ERRCODE = 'P0001';
  END IF;
  UPDATE public.weekly_report SET status = 'draft', updated_at = clock_timestamp() WHERE office_id = actor.actor_office_id AND id = p_report_id;
  PERFORM public.phase12_write_audit_internal(
    'weekly_report.returned_to_draft', 'weekly_report', p_report_id, actor.actor_office_id, actor.actor_id,
    jsonb_build_object('before_status', 'awaiting_review', 'after_status', 'draft', 'version_number', version_row.version_number,
                       'content_hash', version_row.content_hash, 'result', 'returned', 'idempotency_key', p_idempotency_key,
                       'correlation_id', gen_random_uuid())
  );
  PERFORM public.phase12_complete_command(actor.actor_office_id, 'report.return', p_idempotency_key, p_report_id, p_version_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_approve_report(
  p_report_id UUID,
  p_version_id UUID,
  p_idempotency_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  report_row public.weekly_report%ROWTYPE;
  version_row public.report_version%ROWTYPE;
  computed_hash TEXT;
  fingerprint TEXT;
  old_report_id UUID;
  old_version_id UUID;
  replay BOOLEAN;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role <> 'lawyer' THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('juridico.phase12_internal', '1', true);
  SELECT * INTO report_row FROM public.weekly_report WHERE office_id = actor.actor_office_id AND id = p_report_id FOR UPDATE;
  SELECT * INTO version_row FROM public.report_version WHERE office_id = actor.actor_office_id AND id = p_version_id AND report_id = p_report_id;
  IF report_row.id IS NULL OR version_row.id IS NULL OR report_row.current_version_id IS DISTINCT FROM p_version_id THEN
    RAISE EXCEPTION 'invalid report approval' USING ERRCODE = 'P0001';
  END IF;
  computed_hash := public.phase12_hash_version(
    version_row.schema_version, report_row.period_start_utc, report_row.period_end_utc,
    version_row.structured_content, version_row.source_manifest
  );
  IF computed_hash IS DISTINCT FROM version_row.content_hash THEN
    RAISE EXCEPTION 'report version hash mismatch' USING ERRCODE = '23514';
  END IF;
  fingerprint := encode(extensions.digest(convert_to(jsonb_build_object('report_id', p_report_id, 'version_id', p_version_id, 'hash', computed_hash)::TEXT, 'UTF8'), 'sha256'), 'hex');
  SELECT * INTO old_report_id, old_version_id, replay FROM public.phase12_register_command(actor.actor_office_id, 'report.approve', p_idempotency_key, fingerprint, p_report_id);
  IF replay THEN RETURN; END IF;
  IF report_row.status <> 'awaiting_review' THEN
    RAISE EXCEPTION 'invalid report approval' USING ERRCODE = 'P0001';
  END IF;
  UPDATE public.weekly_report
     SET status = 'approved', approved_version_id = p_version_id, approved_hash = computed_hash,
         approved_by = actor.actor_id, approved_at = clock_timestamp(), updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = p_report_id;
  PERFORM public.phase12_write_audit_internal(
    'weekly_report.approved', 'weekly_report', p_report_id, actor.actor_office_id, actor.actor_id,
    jsonb_build_object('before_status', 'awaiting_review', 'after_status', 'approved',
                       'version_number', version_row.version_number, 'content_hash', computed_hash,
                       'approved_hash', computed_hash, 'result', 'approved', 'idempotency_key', p_idempotency_key,
                       'correlation_id', gen_random_uuid())
  );
  PERFORM public.phase12_complete_command(actor.actor_office_id, 'report.approve', p_idempotency_key, p_report_id, p_version_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.phase12_cancel_report(
  p_report_id UUID,
  p_reason_code TEXT,
  p_idempotency_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  report_row public.weekly_report%ROWTYPE;
  fingerprint TEXT;
  old_report_id UUID;
  old_version_id UUID;
  replay BOOLEAN;
BEGIN
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role <> 'lawyer' THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;
  IF p_reason_code NOT IN ('duplicate', 'incorrect_content', 'no_longer_required', 'other') THEN
    RAISE EXCEPTION 'invalid cancellation reason' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('juridico.phase12_internal', '1', true);
  fingerprint := encode(extensions.digest(convert_to(jsonb_build_object('report_id', p_report_id, 'reason_code', p_reason_code)::TEXT, 'UTF8'), 'sha256'), 'hex');
  SELECT * INTO old_report_id, old_version_id, replay FROM public.phase12_register_command(actor.actor_office_id, 'report.cancel', p_idempotency_key, fingerprint, p_report_id);
  IF replay THEN RETURN; END IF;
  SELECT * INTO report_row FROM public.weekly_report WHERE office_id = actor.actor_office_id AND id = p_report_id FOR UPDATE;
  IF report_row.id IS NULL OR report_row.status NOT IN ('draft', 'awaiting_review', 'approved') THEN
    RAISE EXCEPTION 'report cannot be cancelled' USING ERRCODE = 'P0001';
  END IF;
  UPDATE public.weekly_report
     SET status = 'cancelled', cancelled_by = actor.actor_id, cancelled_at = clock_timestamp(),
         cancel_reason_code = p_reason_code, updated_at = clock_timestamp()
   WHERE office_id = actor.actor_office_id AND id = p_report_id;
  PERFORM public.phase12_write_audit_internal(
    'weekly_report.cancelled', 'weekly_report', p_report_id, actor.actor_office_id, actor.actor_id,
    jsonb_build_object('before_status', report_row.status, 'after_status', 'cancelled',
                       'version_number', (SELECT version_number FROM public.report_version WHERE office_id = actor.actor_office_id AND id = report_row.current_version_id),
                       'approved_hash', report_row.approved_hash, 'reason_code', p_reason_code,
                       'result', 'cancelled', 'idempotency_key', p_idempotency_key,
                       'correlation_id', gen_random_uuid())
  );
  PERFORM public.phase12_complete_command(actor.actor_office_id, 'report.cancel', p_idempotency_key, p_report_id, report_row.current_version_id);
END;
$$;

ALTER TABLE public.weekly_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_process ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_party ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_command_idempotency ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.weekly_report, public.report_version, public.report_process,
  public.report_party, public.report_command_idempotency
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.weekly_report, public.report_version, public.report_process, public.report_party TO authenticated;

CREATE POLICY weekly_report_select_authorized
ON public.weekly_report FOR SELECT TO authenticated
USING (public.phase12_can_view_report_row(office_id));

CREATE POLICY report_version_select_authorized
ON public.report_version FOR SELECT TO authenticated
USING (public.phase12_can_view_report_row(office_id));

CREATE POLICY report_process_select_authorized
ON public.report_process FOR SELECT TO authenticated
USING (public.phase12_can_view_report_row(office_id));

CREATE POLICY report_party_select_authorized
ON public.report_party FOR SELECT TO authenticated
USING (public.phase12_can_view_report_row(office_id));

REVOKE ALL ON FUNCTION public.phase12_hash_version(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, JSONB, JSONB) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_validate_editorial(JSONB) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_assert_backend() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase12_build_source_manifest(UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_build_report_content(UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_process_history_proven(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_process_party_history_proven(UUID, UUID, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_period_end_for(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase12_period_start_for(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.phase12_generate_weekly_report(UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phase12_generate_weekly_report(UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ) TO service_role;

REVOKE ALL ON FUNCTION public.phase12_create_editorial_version(UUID, UUID, JSONB, TEXT) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.phase12_restore_report_version(UUID, UUID, UUID, TEXT) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.phase12_submit_report(UUID, UUID, TEXT) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.phase12_return_report_to_draft(UUID, UUID, TEXT) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.phase12_approve_report(UUID, UUID, TEXT) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.phase12_cancel_report(UUID, TEXT, TEXT) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.phase12_create_editorial_version(UUID, UUID, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase12_restore_report_version(UUID, UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase12_submit_report(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase12_return_report_to_draft(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase12_approve_report(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.phase12_cancel_report(UUID, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.phase12_write_audit_internal(TEXT, TEXT, UUID, UUID, UUID, JSONB) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_register_command(UUID, TEXT, TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_complete_command(UUID, TEXT, TEXT, UUID, UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_can_view_report_row(UUID) FROM PUBLIC, anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.report_command_idempotency_id_seq TO postgres;
