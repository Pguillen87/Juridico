-- Preserve the existing portfolio function contract while exposing the
-- normalized fields needed by the lawyer-facing spreadsheet.
CREATE OR REPLACE FUNCTION public.get_client_portfolio_read_model(
  p_client_id UUID DEFAULT NULL
)
RETURNS SETOF JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
WITH visible_clients AS (
  SELECT
    c.id AS client_id,
    p.display_name AS client_name
  FROM public.client c
  JOIN public.party p
    ON p.id = c.party_id
   AND p.office_id = c.office_id
  WHERE c.status = 'active'
    AND (p_client_id IS NULL OR c.id = p_client_id)
), client_processes AS (
  SELECT
    lp.id AS process_id,
    lp.client_id,
    lp.cnj_number,
    lp.tribunal,
    lp.is_public,
    lp.status,
    lp.created_at
  FROM public.legal_process lp
  JOIN visible_clients vc ON vc.client_id = lp.client_id
  WHERE lp.status = 'active'
), latest_job AS (
  SELECT DISTINCT ON (qj.process_id)
    qj.process_id,
    qj.status,
    qj.last_error_code,
    qj.created_at
  FROM public.query_job qj
  JOIN client_processes cp ON cp.process_id = qj.process_id
  ORDER BY qj.process_id, qj.created_at DESC, qj.id DESC
), latest_execution AS (
  SELECT DISTINCT ON (qe.process_id)
    qe.id,
    qe.process_id,
    qe.status,
    qe.error_code,
    qe.finished_at,
    qe.started_at
  FROM public.query_execution qe
  JOIN client_processes cp ON cp.process_id = qe.process_id
  WHERE qe.finished_at IS NOT NULL
  ORDER BY qe.process_id, qe.finished_at DESC, qe.id DESC
), latest_exchange AS (
  SELECT DISTINCT ON (pe.process_id)
    pe.id,
    pe.process_id,
    pe.result_kind,
    pe.result_status,
    pe.error_code,
    pe.created_at
  FROM public.provider_exchange pe
  JOIN client_processes cp ON cp.process_id = pe.process_id
  ORDER BY pe.process_id, pe.created_at DESC, pe.id DESC
), latest_observation AS (
  SELECT DISTINCT ON (pe.process_id)
    pe.id,
    pe.process_id,
    pe.normalized_result,
    pe.created_at
  FROM public.provider_exchange pe
  JOIN client_processes cp ON cp.process_id = pe.process_id
  WHERE pe.result_kind = 'observation'
    AND pe.result_status = 'observed'
  ORDER BY pe.process_id, pe.created_at DESC, pe.id DESC
), latest_comparison AS (
  SELECT DISTINCT ON (pc.process_id)
    pc.id,
    pc.process_id,
    pc.result,
    pc.reason_code,
    pc.normalized_diff,
    pc.created_at,
    current_snapshot.created_at AS snapshot_created_at
  FROM public.process_comparison pc
  JOIN client_processes cp ON cp.process_id = pc.process_id
  JOIN public.process_snapshot current_snapshot
    ON current_snapshot.id = pc.current_snapshot_id
   AND current_snapshot.office_id = pc.office_id
  ORDER BY pc.process_id, current_snapshot.created_at DESC, pc.created_at DESC, pc.id DESC
), recent_movement AS (
  SELECT DISTINCT ON (lo.process_id)
    lo.process_id,
    movement->>'date' AS movement_date,
    movement->>'code' AS movement_code,
    movement->>'type' AS movement_type,
    movement->>'description' AS movement_description,
    movement->'court'->>'name' AS movement_court
  FROM latest_observation lo
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(lo.normalized_result->'data'->'movements') = 'array'
        THEN lo.normalized_result->'data'->'movements'
      ELSE '[]'::jsonb
    END
  ) AS movement
  WHERE movement->>'date' IS NOT NULL
  ORDER BY lo.process_id, movement->>'date' DESC, movement->>'movementRef' DESC
), process_states AS (
  SELECT
    cp.process_id,
    cp.client_id,
    cp.cnj_number,
    cp.tribunal,
    cp.is_public,
    cp.status,
    cp.created_at,
    le.finished_at AS last_consulted_at,
    lo.normalized_result->'sourceMetadata'->>'sourceUpdatedAt'
      AS source_updated_at,
    NULL::TEXT AS source_status,
    lo.normalized_result->'data'->'basicData'->>'filingDate'
      AS filing_date,
    lo.normalized_result->'data'->'basicData'->>'degree'
      AS degree,
    lo.normalized_result->'data'->'basicData'->>'secrecyLevel'
      AS secrecy_level,
    COALESCE(
      lo.normalized_result->'data'->'basicData'->'system'->>'name',
      lo.normalized_result->'data'->>'system'
    ) AS system_name,
    lo.normalized_result->'data'->'basicData'->'processClass'->>'name'
      AS process_class,
    lo.normalized_result->'data'->'basicData'->'court'->>'name'
      AS court,
    rm.movement_date,
    rm.movement_code,
    rm.movement_type,
    rm.movement_description,
    rm.movement_court,
    CASE
      WHEN lj.status IN ('pending', 'running')
        THEN 'updating'
      WHEN lx.result_status = 'manual_review_required'
        OR lx.error_code IN (
          'datajud_multiple_hits_returned',
          'datajud_movement_ambiguity_detected'
        )
        THEN 'manual_review'
      WHEN lj.status IN ('retry_scheduled', 'terminal_failure')
        OR le.status IN ('retry_scheduled', 'terminal_failure')
        OR lx.result_kind = 'failure'
        THEN 'failure'
      WHEN le.id IS NULL OR lo.id IS NULL
        THEN 'not_consulted'
      WHEN lc.result = 'not_comparable'
        AND lc.reason_code = 'first_snapshot'
        THEN 'first_observation'
      WHEN lc.result = 'changed'
        THEN 'changed'
      WHEN lc.result = 'unchanged'
        THEN 'unchanged'
      ELSE 'first_observation'
    END AS state,
    CASE
      WHEN lc.result = 'changed' THEN (
        SELECT count(*)::INTEGER
        FROM jsonb_array_elements(
          CASE
            WHEN jsonb_typeof(lc.normalized_diff->'entries') = 'array'
              THEN lc.normalized_diff->'entries'
            ELSE '[]'::jsonb
          END
        ) AS entry
        WHERE entry->>'changeType' = 'movement_added'
      )
      WHEN lc.result = 'not_comparable'
        AND lc.reason_code = 'first_snapshot'
        THEN jsonb_array_length(
          CASE
            WHEN jsonb_typeof(lo.normalized_result->'data'->'movements') = 'array'
              THEN lo.normalized_result->'data'->'movements'
            ELSE '[]'::jsonb
          END
        )
      ELSE 0
    END AS new_movement_count
  FROM client_processes cp
  LEFT JOIN latest_job lj ON lj.process_id = cp.process_id
  LEFT JOIN latest_execution le ON le.process_id = cp.process_id
  LEFT JOIN latest_exchange lx ON lx.process_id = cp.process_id
  LEFT JOIN latest_observation lo ON lo.process_id = cp.process_id
  LEFT JOIN latest_comparison lc ON lc.process_id = cp.process_id
  LEFT JOIN recent_movement rm ON rm.process_id = cp.process_id
), client_portfolios AS (
  SELECT
    vc.client_id,
    vc.client_name,
    count(ps.process_id)::INTEGER AS process_count,
    count(ps.process_id) FILTER (WHERE ps.state = 'changed')::INTEGER
      AS novelty_count,
    count(ps.process_id) FILTER (WHERE ps.state = 'not_consulted')::INTEGER
      AS not_updated_count,
    count(ps.process_id) FILTER (WHERE ps.state = 'failure')::INTEGER
      AS failure_count,
    count(ps.process_id) FILTER (WHERE ps.state = 'manual_review')::INTEGER
      AS review_count,
    max(ps.last_consulted_at) AS last_consulted_at,
    max(ps.source_updated_at) AS last_source_updated_at,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'processId', ps.process_id,
          'cnjNumber', ps.cnj_number,
          'tribunal', ps.tribunal,
          'isPublic', ps.is_public,
          'officeStatus', ps.status,
          'status', ps.status,
          'sourceStatus', ps.source_status,
          'monitoringState', ps.state,
          'state', ps.state,
          'processClass', ps.process_class,
          'degree', ps.degree,
          'court', ps.court,
          'filingDate', ps.filing_date,
          'secrecyLevel', ps.secrecy_level,
          'system', ps.system_name,
          'lastConsultedAt', ps.last_consulted_at,
          'sourceUpdatedAt', ps.source_updated_at,
          'lastMovement', CASE
            WHEN ps.movement_date IS NULL THEN NULL
            ELSE jsonb_build_object(
              'date', ps.movement_date,
              'code', ps.movement_code,
              'type', ps.movement_type,
              'description', ps.movement_description,
              'court', ps.movement_court
            )
          END,
          'recentMovement', CASE
            WHEN ps.movement_date IS NULL THEN NULL
            ELSE jsonb_build_object(
              'date', ps.movement_date,
              'code', ps.movement_code,
              'type', ps.movement_type,
              'description', ps.movement_description,
              'court', ps.movement_court
            )
          END,
          'hasNews', ps.state = 'changed',
          'newMovementCount', ps.new_movement_count,
          'responsibleName', NULL,
          'nextAction', NULL
        )
        ORDER BY ps.created_at DESC, ps.process_id
      ) FILTER (WHERE ps.process_id IS NOT NULL),
      '[]'::jsonb
    ) AS processes
  FROM visible_clients vc
  LEFT JOIN process_states ps ON ps.client_id = vc.client_id
  GROUP BY vc.client_id, vc.client_name
)
SELECT jsonb_build_object(
  'clientId', client_id,
  'clientName', client_name,
  'processCount', process_count,
  'noveltyCount', novelty_count,
  'notUpdatedCount', not_updated_count,
  'failureCount', failure_count,
  'reviewCount', review_count,
  'lastConsultedAt', last_consulted_at,
  'lastSourceUpdatedAt', last_source_updated_at,
  'processes', processes
)
FROM client_portfolios
ORDER BY client_name, client_id;
$$;

REVOKE ALL ON FUNCTION public.get_client_portfolio_read_model(UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_client_portfolio_read_model(UUID)
  TO authenticated;

COMMENT ON FUNCTION public.get_client_portfolio_read_model(UUID) IS
  'Read model da carteira com campos normalizados separados para a grade.';
