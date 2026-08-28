SET lock_timeout = '2s';

-- Fase 12: hardening forward-safe após a 00005 V2 comprovadamente executável.
-- Inclui somente deltas posteriores e o hash canônico independente da sessão.

ALTER FUNCTION public.phase12_hash_version(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, JSONB, JSONB)
  RENAME TO phase12_hash_version_legacy;

ALTER TABLE public.report_version
  ADD COLUMN hash_algorithm_version TEXT NOT NULL DEFAULT 'phase12-hash-v1'
  CHECK (hash_algorithm_version IN ('phase12-hash-v1', 'phase12-hash-v2-epoch-us'));

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
          'hash_algorithm_version', 'phase12-hash-v2-epoch-us',
          'schema_version', p_schema_version,
          'period_start_epoch_us', round(extract(epoch FROM p_period_start_utc) * 1000000)::BIGINT,
          'period_end_epoch_us', round(extract(epoch FROM p_period_end_utc) * 1000000)::BIGINT,
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
    created_by, creation_kind, schema_version, structured_content, source_manifest, content_hash, hash_algorithm_version
  ) VALUES (
    p_office_id, new_report_id, 1, NULL, NULL, NULL, 'generated', 'report-v1',
    content_value, manifest_value, version_hash, 'phase12-hash-v2-epoch-us'
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
    created_by, creation_kind, schema_version, structured_content, source_manifest, content_hash, hash_algorithm_version
  ) VALUES (
    actor.actor_office_id, report_row.id, new_number, base_version.id, base_version.id,
    actor.actor_id, 'editorial', base_version.schema_version, content_value, manifest_value, content_hash_value, 'phase12-hash-v2-epoch-us'
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
    created_by, creation_kind, schema_version, structured_content, source_manifest, content_hash, hash_algorithm_version
  ) VALUES (
    actor.actor_office_id, report_row.id, new_number, base_version.id, base_version.id, source_version.id,
    actor.actor_id, 'restored', base_version.schema_version, content_value, base_version.source_manifest, content_hash_value, 'phase12-hash-v2-epoch-us'
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
  IF version_row.hash_algorithm_version = 'phase12-hash-v1' THEN
    computed_hash := public.phase12_hash_version_legacy(
      version_row.schema_version, report_row.period_start_utc, report_row.period_end_utc,
      version_row.structured_content, version_row.source_manifest
    );
  ELSE
    computed_hash := public.phase12_hash_version(
      version_row.schema_version, report_row.period_start_utc, report_row.period_end_utc,
      version_row.structured_content, version_row.source_manifest
    );
  END IF;
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


REVOKE ALL ON FUNCTION public.phase12_can_view_report_row(UUID) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.phase12_can_view_report_row(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.phase12_hash_version_legacy(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, JSONB, JSONB) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.phase12_hash_version(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, JSONB, JSONB) FROM PUBLIC, anon, authenticated, service_role;
