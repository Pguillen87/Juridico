-- Server-side filtering for the lawyer-facing process grid.
-- The existing portfolio read model remains the source of truth; this
-- function only narrows its visible processes and recalculates the summary.
CREATE OR REPLACE FUNCTION public.get_client_portfolio_grid(
  p_client_id UUID DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_state TEXT DEFAULT NULL,
  p_is_public BOOLEAN DEFAULT NULL
)
RETURNS SETOF JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
WITH base AS (
  SELECT
    (portfolio.value ->> 'clientId')::UUID AS client_id,
    portfolio.value ->> 'clientName' AS client_name,
    process.value AS process
  FROM public.get_client_portfolio_read_model(p_client_id) AS portfolio(value)
  CROSS JOIN LATERAL jsonb_array_elements(portfolio.value -> 'processes') AS process(value)
), filtered AS (
  SELECT client_id, client_name, process
  FROM base
  WHERE (
    p_search IS NULL
    OR btrim(p_search) = ''
    OR lower(concat_ws(
      ' ',
      client_name,
      process ->> 'cnjNumber',
      process ->> 'tribunal',
      process ->> 'system',
      process ->> 'processClass',
      process ->> 'degree',
      process ->> 'court',
      process -> 'lastMovement' ->> 'type',
      process -> 'lastMovement' ->> 'description'
    )) LIKE '%' || lower(btrim(p_search)) || '%'
    OR (
      regexp_replace(btrim(p_search), '[^0-9]', '', 'g') <> ''
      AND process ->> 'cnjNumber' LIKE '%' || regexp_replace(
        btrim(p_search), '[^0-9]', '', 'g'
      ) || '%'
    )
  )
  AND (
    p_state IS NULL
    OR p_state IN (
      'not_consulted',
      'updating',
      'first_observation',
      'unchanged',
      'changed',
      'failure',
      'manual_review'
    )
    AND process ->> 'monitoringState' = p_state
  )
  AND (
    p_is_public IS NULL
    OR (process ->> 'isPublic')::BOOLEAN = p_is_public
  )
), grouped AS (
  SELECT
    client_id,
    client_name,
    count(*)::INTEGER AS process_count,
    count(*) FILTER (
      WHERE (process ->> 'hasNews')::BOOLEAN
    )::INTEGER AS novelty_count,
    count(*) FILTER (
      WHERE process ->> 'monitoringState' = 'not_consulted'
    )::INTEGER AS not_updated_count,
    count(*) FILTER (
      WHERE process ->> 'monitoringState' = 'failure'
    )::INTEGER AS failure_count,
    count(*) FILTER (
      WHERE process ->> 'monitoringState' = 'manual_review'
    )::INTEGER AS review_count,
    max(nullif(process ->> 'lastConsultedAt', '')) AS last_consulted_at,
    max(nullif(process ->> 'sourceUpdatedAt', '')) AS last_source_updated_at,
    jsonb_agg(process ORDER BY process ->> 'cnjNumber') AS processes
  FROM filtered
  GROUP BY client_id, client_name
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
FROM grouped
ORDER BY client_name, client_id;
$$;

REVOKE ALL ON FUNCTION public.get_client_portfolio_grid(UUID, TEXT, TEXT, BOOLEAN)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_client_portfolio_grid(UUID, TEXT, TEXT, BOOLEAN)
  TO authenticated;

COMMENT ON FUNCTION public.get_client_portfolio_grid(UUID, TEXT, TEXT, BOOLEAN) IS
  'Read model filtrado server-side para a grade operacional de processos.';
