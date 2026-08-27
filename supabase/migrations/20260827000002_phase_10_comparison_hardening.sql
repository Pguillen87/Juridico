SET lock_timeout = '2s';

-- Fase 10 hardening incremental.
-- A migration 00001 permanece byte a byte imutável. Esta migration adiciona
-- somente a resolução de baseline compatível e o contrato RPC completo.

CREATE OR REPLACE FUNCTION public.phase10_resolve_compatible_previous_snapshot(
  p_current_snapshot_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  current_snapshot public.process_snapshot%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  previous_id UUID;
BEGIN
  SELECT ps.* INTO current_snapshot
    FROM public.process_snapshot ps
   WHERE ps.id = p_current_snapshot_id;
  IF current_snapshot.id IS NULL THEN
    RAISE EXCEPTION 'current snapshot not found' USING ERRCODE = '42501';
  END IF;

  SELECT lp.* INTO process_row
    FROM public.legal_process lp
   WHERE lp.id = current_snapshot.process_id
     AND lp.office_id = current_snapshot.office_id;
  IF process_row.id IS NULL THEN
    RAISE EXCEPTION 'snapshot process not found' USING ERRCODE = '42501';
  END IF;

  SELECT ps.id INTO previous_id
    FROM public.process_snapshot ps
    JOIN public.query_execution qe
      ON qe.id = ps.query_execution_id
     AND qe.office_id = ps.office_id
     AND qe.process_id = ps.process_id
    JOIN public.provider_exchange pe
      ON pe.id = qe.provider_exchange_id
     AND pe.office_id = ps.office_id
     AND pe.process_id = ps.process_id
   WHERE ps.office_id = current_snapshot.office_id
     AND ps.process_id = current_snapshot.process_id
     AND ps.provider_id = current_snapshot.provider_id
     AND ps.source = current_snapshot.source
     AND ps.normalizer_version = current_snapshot.normalizer_version
     AND (ps.created_at, ps.id) < (current_snapshot.created_at, current_snapshot.id)
     AND qe.status = 'succeeded'
     AND qe.provider_id = ps.provider_id
     AND pe.provider_id = ps.provider_id
     AND pe.source = ps.source
     AND pe.result_kind = 'observation'
     AND ps.normalized_data->>'processRef' IS NOT DISTINCT FROM process_row.cnj_number
     AND jsonb_typeof(ps.missing_fields) = 'array'
     AND jsonb_array_length(ps.missing_fields) = 0
     AND ps.normalized_data ?& ARRAY[
       'processRef', 'tribunal', 'system', 'movements', 'parties'
     ]
     AND jsonb_typeof(ps.normalized_data->'movements') = 'array'
     AND jsonb_typeof(ps.normalized_data->'parties') = 'array'
     AND NOT EXISTS (
       SELECT 1
         FROM jsonb_array_elements(ps.normalized_data->'movements') AS movement
        WHERE jsonb_typeof(movement->'missingFields') <> 'array'
           OR jsonb_array_length(movement->'missingFields') <> 0
     )
     AND NOT EXISTS (
       SELECT 1
         FROM jsonb_array_elements(ps.normalized_data->'parties') AS party
        WHERE jsonb_typeof(party->'missingFields') <> 'array'
           OR jsonb_array_length(party->'missingFields') <> 0
     )
     AND encode(
       extensions.digest(
         convert_to(ps.normalized_data::TEXT, 'UTF8'), 'sha256'
       ),
       'hex'
     ) = ps.snapshot_hash
     AND NOT public.provider_json_has_comparison(ps.normalized_data)
     AND NOT public.provider_payload_has_sensitive_key(ps.normalized_data)
   ORDER BY ps.created_at DESC, ps.id DESC
   LIMIT 1;

  RETURN previous_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase10_get_snapshot_pair_compatible_internal(
  p_current_snapshot_id UUID
)
RETURNS TABLE (
  snapshot_role TEXT,
  id UUID,
  office_id UUID,
  process_id UUID,
  provider_id TEXT,
  source TEXT,
  normalizer_version TEXT,
  normalized_data JSONB,
  missing_fields JSONB,
  snapshot_hash TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  current_snapshot public.process_snapshot%ROWTYPE;
  previous_snapshot public.process_snapshot%ROWTYPE;
BEGIN
  SELECT ps.* INTO current_snapshot
    FROM public.process_snapshot ps
   WHERE ps.id = p_current_snapshot_id;
  IF current_snapshot.id IS NULL THEN
    RAISE EXCEPTION 'current snapshot not found' USING ERRCODE = '42501';
  END IF;

  SELECT ps.* INTO previous_snapshot
    FROM public.process_snapshot ps
   WHERE ps.id = public.phase10_resolve_compatible_previous_snapshot(
     current_snapshot.id
   );

  snapshot_role := 'current';
  id := current_snapshot.id;
  office_id := current_snapshot.office_id;
  process_id := current_snapshot.process_id;
  provider_id := current_snapshot.provider_id;
  source := current_snapshot.source;
  normalizer_version := current_snapshot.normalizer_version;
  normalized_data := current_snapshot.normalized_data;
  missing_fields := current_snapshot.missing_fields;
  snapshot_hash := current_snapshot.snapshot_hash;
  created_at := current_snapshot.created_at;
  RETURN NEXT;

  IF previous_snapshot.id IS NOT NULL THEN
    snapshot_role := 'previous';
    id := previous_snapshot.id;
    office_id := previous_snapshot.office_id;
    process_id := previous_snapshot.process_id;
    provider_id := previous_snapshot.provider_id;
    source := previous_snapshot.source;
    normalizer_version := previous_snapshot.normalizer_version;
    normalized_data := previous_snapshot.normalized_data;
    missing_fields := previous_snapshot.missing_fields;
    snapshot_hash := previous_snapshot.snapshot_hash;
    created_at := previous_snapshot.created_at;
    RETURN NEXT;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.phase10_compare_process_snapshot_v2(
  p_current_snapshot_id UUID,
  p_comparison_version TEXT,
  p_result TEXT,
  p_reason_code TEXT,
  p_changed_fields JSONB,
  p_normalized_diff JSONB
)
RETURNS TABLE (
  comparison_id UUID,
  detected_change_id UUID,
  result TEXT,
  reason_code TEXT,
  comparison_hash TEXT,
  changed_fields JSONB,
  normalized_diff JSONB,
  replayed BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  current_snapshot public.process_snapshot%ROWTYPE;
  previous_snapshot public.process_snapshot%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  current_execution public.query_execution%ROWTYPE;
  current_exchange public.provider_exchange%ROWTYPE;
  previous_execution public.query_execution%ROWTYPE;
  previous_exchange public.provider_exchange%ROWTYPE;
  current_snapshot_invalid BOOLEAN;
  previous_snapshot_invalid BOOLEAN := false;
  comparison_uuid UUID;
  detected_uuid UUID;
  existing_hash TEXT;
  computed_hash TEXT;
  inserted BOOLEAN := false;
  current_complete BOOLEAN;
  previous_complete BOOLEAN;
  previous_exists BOOLEAN;
BEGIN
  IF p_current_snapshot_id IS NULL
     OR p_comparison_version IS NULL
     OR p_comparison_version <> 'comparison-v1'
  THEN
    RAISE EXCEPTION 'comparison version is not allowlisted'
      USING ERRCODE = '22023';
  END IF;
  IF p_result NOT IN ('changed', 'unchanged', 'not_comparable') THEN
    RAISE EXCEPTION 'invalid comparison result' USING ERRCODE = '22023';
  END IF;
  IF p_reason_code IS NOT NULL AND p_reason_code NOT IN (
    'first_snapshot', 'normalizer_incompatible', 'source_incompatible',
    'required_field_missing', 'snapshot_invalid', 'baseline_incomplete',
    'field_presence_incompatible'
  ) THEN
    RAISE EXCEPTION 'comparison reason is not allowlisted' USING ERRCODE = '22023';
  END IF;
  IF p_result = 'not_comparable' AND p_reason_code IS NULL THEN
    RAISE EXCEPTION 'not_comparable requires an allowlisted reason'
      USING ERRCODE = '22023';
  END IF;
  IF p_result <> 'not_comparable' AND p_reason_code IS NOT NULL THEN
    RAISE EXCEPTION 'changed/unchanged cannot have a comparison reason'
      USING ERRCODE = '22023';
  END IF;
  IF p_changed_fields IS NULL OR jsonb_typeof(p_changed_fields) <> 'array'
     OR jsonb_array_length(p_changed_fields) > 200
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_changed_fields) AS field_value
       WHERE jsonb_typeof(field_value) <> 'string'
          OR char_length(btrim(field_value #>> '{}')) NOT BETWEEN 1 AND 512
     )
  THEN
    RAISE EXCEPTION 'invalid comparison changed_fields' USING ERRCODE = '22023';
  END IF;
  IF p_normalized_diff IS NULL
     OR jsonb_typeof(p_normalized_diff) <> 'object'
     OR jsonb_typeof(p_normalized_diff->'entries') <> 'array'
     OR jsonb_array_length(p_normalized_diff->'entries') > 200
     OR EXISTS (
       SELECT 1
         FROM jsonb_array_elements(p_normalized_diff->'entries') AS entry
        WHERE jsonb_typeof(entry) <> 'object'
           OR char_length(btrim(entry->>'path')) NOT BETWEEN 1 AND 512
           OR entry->>'changeType' NOT IN (
             'field_updated', 'movement_added', 'movement_removed',
             'movement_updated', 'party_added', 'party_removed',
             'party_updated'
           )
           OR entry ?| ARRAY['rawPayload', 'headers', 'token', 'credential', 'stackTrace']
     )
  THEN
    RAISE EXCEPTION 'invalid or unsafe comparison diff' USING ERRCODE = '22023';
  END IF;
  IF p_changed_fields IS DISTINCT FROM COALESCE(
       (
         SELECT jsonb_agg(entry->>'path' ORDER BY ordinality)
           FROM jsonb_array_elements(p_normalized_diff->'entries')
             WITH ORDINALITY AS diff_entry(entry, ordinality)
       ),
       '[]'::jsonb
     )
  THEN
    RAISE EXCEPTION 'changed_fields must match normalized_diff paths'
      USING ERRCODE = '22023';
  END IF;
  IF p_result = 'changed'
     AND (jsonb_array_length(p_changed_fields) = 0
          OR jsonb_array_length(p_normalized_diff->'entries') = 0)
  THEN
    RAISE EXCEPTION 'changed comparison requires a non-empty diff'
      USING ERRCODE = '22023';
  END IF;
  IF p_result IN ('unchanged', 'not_comparable')
     AND (jsonb_array_length(p_changed_fields) <> 0
          OR jsonb_array_length(p_normalized_diff->'entries') <> 0)
  THEN
    RAISE EXCEPTION 'unchanged/not_comparable cannot persist a diff'
      USING ERRCODE = '22023';
  END IF;

  SELECT ps.* INTO current_snapshot
    FROM public.process_snapshot ps
   WHERE ps.id = p_current_snapshot_id;
  IF current_snapshot.id IS NULL THEN
    RAISE EXCEPTION 'current snapshot not found' USING ERRCODE = '42501';
  END IF;

  PERFORM 1
    FROM public.legal_process lp
   WHERE lp.id = current_snapshot.process_id
     AND lp.office_id = current_snapshot.office_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'snapshot process not found' USING ERRCODE = '42501';
  END IF;

  SELECT lp.* INTO process_row
    FROM public.legal_process lp
   WHERE lp.id = current_snapshot.process_id
     AND lp.office_id = current_snapshot.office_id;
  SELECT qe.* INTO current_execution
    FROM public.query_execution qe
   WHERE qe.id = current_snapshot.query_execution_id
     AND qe.office_id = current_snapshot.office_id
     AND qe.process_id = current_snapshot.process_id;
  SELECT pe.* INTO current_exchange
    FROM public.provider_exchange pe
   WHERE pe.id = current_execution.provider_exchange_id
     AND pe.office_id = current_snapshot.office_id
     AND pe.process_id = current_snapshot.process_id;
  current_snapshot_invalid := current_execution.id IS NULL
     OR current_execution.status <> 'succeeded'
     OR current_exchange.id IS NULL OR current_exchange.result_kind <> 'observation'
     OR current_snapshot.provider_id <> current_exchange.provider_id
     OR current_snapshot.source <> current_exchange.source
     OR current_snapshot.normalized_data->>'processRef' IS DISTINCT FROM process_row.cnj_number
     OR encode(extensions.digest(convert_to(current_snapshot.normalized_data::TEXT, 'UTF8'), 'sha256'), 'hex')
          <> current_snapshot.snapshot_hash
     OR public.provider_json_has_comparison(current_snapshot.normalized_data)
     OR public.provider_payload_has_sensitive_key(current_snapshot.normalized_data);
  IF current_snapshot_invalid
     AND (p_result <> 'not_comparable' OR p_reason_code <> 'snapshot_invalid')
  THEN
    RAISE EXCEPTION 'current snapshot is not valid for comparison'
      USING ERRCODE = '42501';
  END IF;

  current_complete := CASE
    WHEN jsonb_typeof(current_snapshot.missing_fields) <> 'array' THEN false
    WHEN jsonb_array_length(current_snapshot.missing_fields) <> 0 THEN false
    WHEN NOT (current_snapshot.normalized_data ?& ARRAY['processRef', 'tribunal', 'system', 'movements', 'parties']) THEN false
    WHEN jsonb_typeof(current_snapshot.normalized_data->'movements') <> 'array' THEN false
    WHEN jsonb_typeof(current_snapshot.normalized_data->'parties') <> 'array' THEN false
    ELSE (
      NOT EXISTS (
        SELECT 1
          FROM jsonb_array_elements(current_snapshot.normalized_data->'movements') AS movement
         WHERE jsonb_typeof(movement->'missingFields') <> 'array'
            OR jsonb_array_length(movement->'missingFields') <> 0
      )
      AND NOT EXISTS (
        SELECT 1
          FROM jsonb_array_elements(current_snapshot.normalized_data->'parties') AS party
         WHERE jsonb_typeof(party->'missingFields') <> 'array'
            OR jsonb_array_length(party->'missingFields') <> 0
      )
    )
  END;

  SELECT ps.* INTO previous_snapshot
    FROM public.process_snapshot ps
   WHERE ps.id = public.phase10_resolve_compatible_previous_snapshot(
     current_snapshot.id
   );
  previous_exists := previous_snapshot.id IS NOT NULL;
  IF previous_exists THEN
    SELECT qe.* INTO previous_execution
      FROM public.query_execution qe
     WHERE qe.id = previous_snapshot.query_execution_id
       AND qe.office_id = previous_snapshot.office_id
       AND qe.process_id = previous_snapshot.process_id;
    SELECT pe.* INTO previous_exchange
      FROM public.provider_exchange pe
     WHERE pe.id = previous_execution.provider_exchange_id
       AND pe.office_id = previous_snapshot.office_id
       AND pe.process_id = previous_snapshot.process_id;
    previous_snapshot_invalid := previous_execution.id IS NULL
       OR previous_execution.status <> 'succeeded'
       OR previous_exchange.id IS NULL OR previous_exchange.result_kind <> 'observation'
       OR previous_snapshot.provider_id <> previous_exchange.provider_id
       OR previous_snapshot.source <> previous_exchange.source
       OR previous_snapshot.normalized_data->>'processRef' IS DISTINCT FROM process_row.cnj_number
       OR encode(extensions.digest(convert_to(previous_snapshot.normalized_data::TEXT, 'UTF8'), 'sha256'), 'hex')
            <> previous_snapshot.snapshot_hash
       OR public.provider_json_has_comparison(previous_snapshot.normalized_data)
       OR public.provider_payload_has_sensitive_key(previous_snapshot.normalized_data);
    IF previous_snapshot_invalid
       AND (p_result <> 'not_comparable' OR p_reason_code <> 'snapshot_invalid')
    THEN
      RAISE EXCEPTION 'previous snapshot is not valid for comparison'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  previous_complete := CASE
    WHEN NOT previous_exists THEN false
    WHEN jsonb_typeof(previous_snapshot.missing_fields) <> 'array' THEN false
    WHEN jsonb_array_length(previous_snapshot.missing_fields) <> 0 THEN false
    WHEN NOT (previous_snapshot.normalized_data ?& ARRAY['processRef', 'tribunal', 'system', 'movements', 'parties']) THEN false
    WHEN jsonb_typeof(previous_snapshot.normalized_data->'movements') <> 'array' THEN false
    WHEN jsonb_typeof(previous_snapshot.normalized_data->'parties') <> 'array' THEN false
    ELSE (
      NOT EXISTS (
        SELECT 1
          FROM jsonb_array_elements(previous_snapshot.normalized_data->'movements') AS movement
         WHERE jsonb_typeof(movement->'missingFields') <> 'array'
            OR jsonb_array_length(movement->'missingFields') <> 0
      )
      AND NOT EXISTS (
        SELECT 1
          FROM jsonb_array_elements(previous_snapshot.normalized_data->'parties') AS party
         WHERE jsonb_typeof(party->'missingFields') <> 'array'
            OR jsonb_array_length(party->'missingFields') <> 0
      )
    )
  END;

  IF current_snapshot_invalid OR previous_snapshot_invalid THEN
    IF p_result <> 'not_comparable' OR p_reason_code <> 'snapshot_invalid' THEN
      RAISE EXCEPTION 'invalid snapshots must be snapshot_invalid'
        USING ERRCODE = '22023';
    END IF;
  ELSIF NOT previous_exists THEN
    IF p_result <> 'not_comparable' OR p_reason_code <> 'first_snapshot' THEN
      RAISE EXCEPTION 'first snapshot must be not_comparable'
        USING ERRCODE = '22023';
    END IF;
  ELSIF current_snapshot.normalizer_version <> previous_snapshot.normalizer_version THEN
    IF p_result <> 'not_comparable' OR p_reason_code <> 'normalizer_incompatible' THEN
      RAISE EXCEPTION 'normalizer incompatibility must be not_comparable'
        USING ERRCODE = '22023';
    END IF;
  ELSIF current_snapshot.provider_id <> previous_snapshot.provider_id
     OR current_snapshot.source <> previous_snapshot.source
  THEN
    IF p_result <> 'not_comparable' OR p_reason_code <> 'source_incompatible' THEN
      RAISE EXCEPTION 'source incompatibility must be not_comparable'
        USING ERRCODE = '22023';
    END IF;
  ELSIF NOT current_complete OR NOT previous_complete THEN
    IF p_result <> 'not_comparable'
       OR p_reason_code NOT IN ('required_field_missing', 'baseline_incomplete')
    THEN
      RAISE EXCEPTION 'incomplete snapshots must be not_comparable'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  computed_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'changedFields', p_changed_fields,
          'comparisonVersion', p_comparison_version,
          'currentSnapshotId', current_snapshot.id,
          'normalizedDiff', p_normalized_diff,
          'previousSnapshotId', CASE WHEN previous_exists THEN previous_snapshot.id ELSE NULL END,
          'reasonCode', p_reason_code,
          'result', p_result
        )::TEXT,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  INSERT INTO public.process_comparison (
    office_id, process_id, previous_snapshot_id, current_snapshot_id,
    comparison_version, result, reason_code, changed_fields, normalized_diff,
    comparison_hash
  ) VALUES (
    current_snapshot.office_id, current_snapshot.process_id,
    CASE WHEN previous_exists THEN previous_snapshot.id ELSE NULL END,
    current_snapshot.id, p_comparison_version, p_result, p_reason_code,
    p_changed_fields, p_normalized_diff, computed_hash
  )
  ON CONFLICT (office_id, process_id, current_snapshot_id, comparison_version)
  DO NOTHING
  RETURNING id INTO comparison_uuid;
  inserted := comparison_uuid IS NOT NULL;

  IF NOT inserted THEN
    SELECT pc.id, pc.comparison_hash
      INTO comparison_uuid, existing_hash
      FROM public.process_comparison pc
     WHERE pc.office_id = current_snapshot.office_id
       AND pc.process_id = current_snapshot.process_id
       AND pc.current_snapshot_id = current_snapshot.id
       AND pc.comparison_version = p_comparison_version;
    IF comparison_uuid IS NULL OR existing_hash <> computed_hash THEN
      RAISE EXCEPTION 'comparison replay conflicts with existing result'
        USING ERRCODE = '40001';
    END IF;
  ELSE
    IF p_result = 'not_comparable' THEN
      PERFORM public.phase10_write_system_audit(
        'comparison.not_comparable', 'process_comparison', comparison_uuid,
        current_snapshot.office_id, current_snapshot.process_id, comparison_uuid,
        p_result, p_reason_code, md5(current_execution.correlation_id)::uuid
      );
    ELSE
      PERFORM public.phase10_write_system_audit(
        'comparison.completed', 'process_comparison', comparison_uuid,
        current_snapshot.office_id, current_snapshot.process_id, comparison_uuid,
        p_result, NULL, md5(current_execution.correlation_id)::uuid
      );
    END IF;
  END IF;

  IF p_result = 'changed' THEN
    INSERT INTO public.detected_change (
      office_id, process_id, comparison_id, change_fingerprint, change_type
    ) VALUES (
      current_snapshot.office_id, current_snapshot.process_id, comparison_uuid,
      computed_hash, 'snapshot_changed'
    )
    ON CONFLICT ON CONSTRAINT detected_change_office_id_comparison_id_key
    DO NOTHING
    RETURNING id INTO detected_uuid;
    IF detected_uuid IS NOT NULL THEN
      PERFORM public.phase10_write_system_audit(
        'detected_change.created', 'detected_change', detected_uuid,
        current_snapshot.office_id, current_snapshot.process_id, comparison_uuid,
        p_result, NULL, md5(current_execution.correlation_id)::uuid
      );
    ELSE
      SELECT dc.id INTO detected_uuid
        FROM public.detected_change dc
       WHERE dc.office_id = current_snapshot.office_id
         AND dc.comparison_id = comparison_uuid;
    END IF;
  END IF;

  RETURN QUERY
  SELECT comparison_uuid, detected_uuid, pc.result, pc.reason_code,
         pc.comparison_hash, pc.changed_fields, pc.normalized_diff,
         NOT inserted
    FROM public.process_comparison pc
   WHERE pc.id = comparison_uuid;
END;
$$;

-- O caminho publicado permanece preservado para rollback, mas não é mais
-- executável pelo backend: o wrapper usa somente as funções compatíveis abaixo.
REVOKE ALL ON FUNCTION public.phase10_get_snapshot_pair_internal(UUID)
  FROM service_role;
REVOKE ALL ON FUNCTION public.phase10_compare_process_snapshot(
  UUID, TEXT, TEXT, TEXT, JSONB, JSONB
) FROM service_role;

REVOKE ALL ON FUNCTION public.phase10_resolve_compatible_previous_snapshot(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phase10_resolve_compatible_previous_snapshot(UUID)
  TO service_role;
REVOKE ALL ON FUNCTION public.phase10_get_snapshot_pair_compatible_internal(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phase10_get_snapshot_pair_compatible_internal(UUID)
  TO service_role;
REVOKE ALL ON FUNCTION public.phase10_compare_process_snapshot_v2(
  UUID, TEXT, TEXT, TEXT, JSONB, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phase10_compare_process_snapshot_v2(
  UUID, TEXT, TEXT, TEXT, JSONB, JSONB
) TO service_role;

COMMENT ON FUNCTION public.phase10_resolve_compatible_previous_snapshot(UUID) IS
  'Fase 10 hardening: resolve o snapshot histórico válido mais recente compatível.';
COMMENT ON FUNCTION public.phase10_get_snapshot_pair_compatible_internal(UUID) IS
  'Fase 10 hardening: retorna snapshot atual e baseline histórica compatível; backend-only.';
COMMENT ON FUNCTION public.phase10_compare_process_snapshot_v2(
  UUID, TEXT, TEXT, TEXT, JSONB, JSONB
) IS
  'Fase 10 hardening: persiste comparação idempotente e devolve exatamente o diff persistido.';
