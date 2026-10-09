SET lock_timeout = '2s';

-- Carteira em lote: um lote pai representa uma ação do advogado; cada
-- processo continua sendo executado pelo fluxo individual do R1.
ALTER TABLE public.user_profile
  ADD CONSTRAINT user_profile_office_id_id_key UNIQUE (office_id, id);

ALTER TABLE public.legal_process
  ADD COLUMN responsible_user_id UUID,
  ADD COLUMN next_action TEXT
    CHECK (next_action IS NULL OR char_length(btrim(next_action)) BETWEEN 1 AND 500);

ALTER TABLE public.legal_process
  ADD CONSTRAINT legal_process_responsible_user_fk
  FOREIGN KEY (office_id, responsible_user_id)
  REFERENCES public.user_profile(office_id, id)
  ON DELETE RESTRICT;

CREATE INDEX legal_process_responsible_user_idx
  ON public.legal_process (office_id, client_id, responsible_user_id);

CREATE TABLE public.process_refresh_batch (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
  client_id UUID NOT NULL,
  requested_by UUID NOT NULL,
  provider_id TEXT NOT NULL CHECK (provider_id = 'datajud_public'),
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'running', 'completed', 'completed_with_issues', 'cancelled')),
  total_count INTEGER NOT NULL DEFAULT 0 CHECK (total_count >= 0),
  eligible_count INTEGER NOT NULL DEFAULT 0 CHECK (eligible_count >= 0),
  skipped_count INTEGER NOT NULL DEFAULT 0 CHECK (skipped_count >= 0),
  pending_count INTEGER NOT NULL DEFAULT 0 CHECK (pending_count >= 0),
  running_count INTEGER NOT NULL DEFAULT 0 CHECK (running_count >= 0),
  completed_count INTEGER NOT NULL DEFAULT 0 CHECK (completed_count >= 0),
  novelty_count INTEGER NOT NULL DEFAULT 0 CHECK (novelty_count >= 0),
  unchanged_count INTEGER NOT NULL DEFAULT 0 CHECK (unchanged_count >= 0),
  failure_count INTEGER NOT NULL DEFAULT 0 CHECK (failure_count >= 0),
  review_count INTEGER NOT NULL DEFAULT 0 CHECK (review_count >= 0),
  ignored_count INTEGER NOT NULL DEFAULT 0 CHECK (ignored_count >= 0),
  correlation_id UUID NOT NULL DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  UNIQUE (office_id, id),
  FOREIGN KEY (office_id, client_id)
    REFERENCES public.client(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (requested_by)
    REFERENCES public.user_profile(id) ON DELETE RESTRICT,
  CHECK (eligible_count + skipped_count = total_count),
  CHECK (pending_count <= eligible_count),
  CHECK (running_count <= eligible_count),
  CHECK (completed_count <= eligible_count),
  CHECK (failure_count + review_count + unchanged_count + novelty_count <= completed_count),
  CHECK ((status = 'queued' AND started_at IS NULL)
    OR status <> 'queued'),
  CHECK ((status IN ('completed', 'completed_with_issues', 'cancelled') AND finished_at IS NOT NULL)
    OR status IN ('queued', 'running'))
);

CREATE UNIQUE INDEX process_refresh_batch_one_active_per_client_idx
  ON public.process_refresh_batch (office_id, client_id)
  WHERE status IN ('queued', 'running');

CREATE INDEX process_refresh_batch_client_idx
  ON public.process_refresh_batch (office_id, client_id, created_at DESC);

ALTER TABLE public.process_refresh_batch ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.process_refresh_batch FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.process_refresh_batch TO authenticated;
GRANT SELECT ON public.process_refresh_batch TO service_role;

CREATE POLICY process_refresh_batch_select_same_office
ON public.process_refresh_batch
FOR SELECT TO authenticated
USING (public.can_view_operational_row(office_id));

ALTER TABLE public.query_job
  ADD COLUMN batch_id UUID;

ALTER TABLE public.query_job
  ADD CONSTRAINT query_job_batch_fk
  FOREIGN KEY (office_id, batch_id)
  REFERENCES public.process_refresh_batch(office_id, id)
  ON DELETE RESTRICT;

CREATE INDEX query_job_batch_claim_idx
  ON public.query_job (office_id, batch_id, status, available_at, created_at);

-- Atribuir um job individual já aberto a um novo lote é permitido somente uma
-- vez, pelo contexto interno da RPC. Jobs já pertencentes a outro lote não
-- podem ser movidos.
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
     OR (OLD.batch_id IS NOT NULL AND OLD.batch_id IS DISTINCT FROM NEW.batch_id)
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

CREATE OR REPLACE FUNCTION public.realignment1_write_portfolio_audit(
  p_action TEXT,
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
  IF p_action <> 'process_refresh_batch.requested'
     OR p_entity_id IS NULL
     OR p_metadata IS NULL
     OR jsonb_typeof(p_metadata) <> 'object'
  THEN
    RAISE EXCEPTION 'invalid portfolio audit input' USING ERRCODE = '22023';
  END IF;
  FOR metadata_key IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF metadata_key NOT IN ('eligible_count', 'skipped_count', 'total_count') THEN
      RAISE EXCEPTION 'portfolio audit metadata key is not allowlisted'
        USING ERRCODE = '22023';
    END IF;
  END LOOP;
  INSERT INTO public.audit_log (
    audit_scope, office_id, actor_user_id, action, entity_type, entity_id, metadata
  ) VALUES (
    'operational', actor.actor_office_id, actor.actor_id, p_action,
    'process_refresh_batch', p_entity_id, p_metadata
  ) RETURNING id INTO audit_id;
  RETURN audit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.realignment1_write_portfolio_audit(TEXT, UUID, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.realignment1_write_portfolio_audit(TEXT, UUID, JSONB)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.realignment1_request_client_portfolio_refresh(
  p_client_id UUID
)
RETURNS TABLE (
  state TEXT,
  eligible_count INTEGER,
  skipped_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
  client_row public.client%ROWTYPE;
  batch_row public.process_refresh_batch%ROWTYPE;
  existing_job public.query_job%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  batch_uuid UUID;
  candidate_count INTEGER := 0;
  eligible INTEGER := 0;
  skipped INTEGER := 0;
BEGIN
  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'client id is required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO actor FROM public.require_active_actor();
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;

  SELECT c.* INTO client_row
    FROM public.client c
   WHERE c.id = p_client_id
     AND c.office_id = actor.actor_office_id
     AND c.status = 'active'
   FOR UPDATE;
  IF client_row.id IS NULL THEN
    RAISE EXCEPTION 'client not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT b.* INTO batch_row
    FROM public.process_refresh_batch b
   WHERE b.office_id = actor.actor_office_id
     AND b.client_id = client_row.id
     AND b.status IN ('queued', 'running')
   ORDER BY b.created_at DESC, b.id DESC
   LIMIT 1
   FOR UPDATE;
  IF batch_row.id IS NOT NULL THEN
    state := 'already_running';
    eligible_count := batch_row.eligible_count;
    skipped_count := batch_row.skipped_count;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT count(*)::INTEGER INTO candidate_count
    FROM public.legal_process lp
   WHERE lp.office_id = actor.actor_office_id
     AND lp.client_id = client_row.id
     AND lp.status = 'active'
     AND lp.is_public = true;
  skipped := (
    SELECT count(*)::INTEGER
      FROM public.legal_process lp
     WHERE lp.office_id = actor.actor_office_id
       AND lp.client_id = client_row.id
  ) - candidate_count;

  INSERT INTO public.process_refresh_batch (
    office_id, client_id, requested_by, provider_id, status,
    total_count, eligible_count, skipped_count, pending_count
  ) VALUES (
    actor.actor_office_id, client_row.id, actor.actor_id, 'datajud_public',
    CASE WHEN candidate_count = 0 THEN 'completed' ELSE 'queued' END,
    candidate_count + skipped, candidate_count, skipped, candidate_count
  ) RETURNING * INTO batch_row;
  batch_uuid := batch_row.id;

  PERFORM set_config('juridico.phase9_internal', '1', true);
  FOR process_row IN
    SELECT lp.*
      FROM public.legal_process lp
     WHERE lp.office_id = actor.actor_office_id
       AND lp.client_id = client_row.id
       AND lp.status = 'active'
       AND lp.is_public = true
     ORDER BY lp.created_at, lp.id
  LOOP
    SELECT qj.* INTO existing_job
      FROM public.query_job qj
     WHERE qj.office_id = actor.actor_office_id
       AND qj.process_id = process_row.id
       AND qj.provider_id = 'datajud_public'
       AND qj.job_kind = 'manual_refresh'
       AND qj.status IN ('pending', 'running', 'retry_scheduled')
     ORDER BY qj.created_at DESC, qj.id DESC
     LIMIT 1
     FOR UPDATE;

    IF existing_job.id IS NOT NULL AND existing_job.batch_id IS NOT NULL THEN
      skipped := skipped + 1;
      CONTINUE;
    END IF;

    IF existing_job.id IS NULL THEN
      INSERT INTO public.query_job (
        office_id, process_id, batch_id, provider_id, capability, job_kind,
        idempotency_key, request_fingerprint, correlation_id, status, created_by
      ) VALUES (
        actor.actor_office_id, process_row.id, batch_uuid, 'datajud_public',
        'process_observation', 'manual_refresh',
        'portfolio:' || batch_uuid::TEXT || ':' || process_row.id::TEXT,
        encode(extensions.digest(
          convert_to('portfolio|' || batch_uuid::TEXT || '|' || process_row.id::TEXT, 'UTF8'),
          'sha256'
        ), 'hex'),
        'portfolio:' || batch_uuid::TEXT || ':' || process_row.id::TEXT,
        'pending', actor.actor_id
      );
    ELSE
      UPDATE public.query_job
         SET batch_id = batch_uuid,
             updated_at = clock_timestamp()
       WHERE office_id = actor.actor_office_id
         AND id = existing_job.id
         AND batch_id IS NULL;
    END IF;
    eligible := eligible + 1;
  END LOOP;

  UPDATE public.process_refresh_batch
     SET status = CASE WHEN eligible = 0 THEN 'completed' ELSE 'queued' END,
         total_count = eligible + skipped,
         eligible_count = eligible,
         skipped_count = skipped,
         pending_count = eligible,
         finished_at = CASE WHEN eligible = 0 THEN clock_timestamp() ELSE NULL END,
         updated_at = clock_timestamp()
   WHERE id = batch_uuid;

  PERFORM public.realignment1_write_portfolio_audit(
    'process_refresh_batch.requested', batch_uuid,
    jsonb_build_object(
      'eligible_count', eligible,
      'skipped_count', skipped,
      'total_count', eligible + skipped
    )
  );

  state := CASE WHEN eligible = 0 THEN 'completed' ELSE 'queued' END;
  eligible_count := eligible;
  skipped_count := skipped;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.realignment1_request_client_portfolio_refresh(UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.realignment1_request_client_portfolio_refresh(UUID)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_client_portfolio_refresh_progress(
  p_client_id UUID
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = pg_catalog, public
AS $$
WITH latest_batch AS (
  SELECT b.*
    FROM public.process_refresh_batch b
    JOIN public.client c
      ON c.office_id = b.office_id
     AND c.id = b.client_id
   WHERE b.client_id = p_client_id
   ORDER BY b.created_at DESC, b.id DESC
   LIMIT 1
), job_counts AS (
  SELECT
    lb.id,
    count(qj.id) FILTER (WHERE qj.status IN ('pending', 'retry_scheduled'))::INTEGER AS pending_count,
    count(qj.id) FILTER (WHERE qj.status = 'running')::INTEGER AS running_count,
    count(qj.id) FILTER (WHERE qj.status = 'succeeded')::INTEGER AS completed_count,
    count(qj.id) FILTER (WHERE qj.status = 'terminal_failure')::INTEGER AS failure_count,
    max(qj.updated_at) AS last_job_update,
    count(DISTINCT qj.process_id) FILTER (WHERE latest_comparison.result = 'changed')::INTEGER AS novelty_count,
    count(DISTINCT qj.process_id) FILTER (WHERE latest_comparison.result = 'unchanged')::INTEGER AS unchanged_count,
    count(DISTINCT qj.process_id) FILTER (WHERE latest_exchange.result_status = 'manual_review_required')::INTEGER AS review_count
  FROM latest_batch lb
  LEFT JOIN public.query_job qj
    ON qj.office_id = lb.office_id
   AND qj.batch_id = lb.id
  LEFT JOIN LATERAL (
    SELECT pc.result
      FROM public.process_comparison pc
     WHERE pc.office_id = qj.office_id
       AND pc.process_id = qj.process_id
     ORDER BY pc.created_at DESC, pc.id DESC
     LIMIT 1
  ) latest_comparison ON true
  LEFT JOIN LATERAL (
    SELECT pe.result_status
      FROM public.provider_exchange pe
     WHERE pe.office_id = qj.office_id
       AND pe.process_id = qj.process_id
     ORDER BY pe.created_at DESC, pe.id DESC
     LIMIT 1
  ) latest_exchange ON true
  GROUP BY lb.id
)
SELECT CASE
  WHEN lb.id IS NULL THEN NULL::JSONB
  ELSE jsonb_build_object(
    'state', CASE
      WHEN coalesce(jc.pending_count, 0) + coalesce(jc.running_count, 0) > 0
        THEN CASE WHEN lb.status = 'queued' THEN 'queued' ELSE 'running' END
      WHEN coalesce(jc.failure_count, 0) + coalesce(jc.review_count, 0) > 0
        THEN 'completed_with_issues'
      ELSE 'completed'
    END,
    'totalCount', lb.total_count,
    'eligibleCount', lb.eligible_count,
    'skippedCount', lb.skipped_count,
    'pendingCount', coalesce(jc.pending_count, 0),
    'runningCount', coalesce(jc.running_count, 0),
    'completedCount', coalesce(jc.completed_count, 0),
    'noveltyCount', coalesce(jc.novelty_count, 0),
    'unchangedCount', coalesce(jc.unchanged_count, 0),
    'failureCount', coalesce(jc.failure_count, 0),
    'reviewCount', coalesce(jc.review_count, 0),
    'lastUpdatedAt', greatest(lb.updated_at, coalesce(jc.last_job_update, lb.updated_at))
  )
END
FROM latest_batch lb
LEFT JOIN job_counts jc ON jc.id = lb.id;
$$;

REVOKE ALL ON FUNCTION public.get_client_portfolio_refresh_progress(UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_client_portfolio_refresh_progress(UUID)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.realignment1_claim_client_portfolio_job(
  p_batch_id UUID,
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
  batch_row public.process_refresh_batch%ROWTYPE;
  job_row public.query_job%ROWTYPE;
  process_row public.legal_process%ROWTYPE;
  execution_uuid UUID;
  token UUID;
  expires_at TIMESTAMPTZ;
  execution_correlation TEXT;
BEGIN
  IF p_batch_id IS NULL
     OR p_worker_id IS NULL
     OR p_worker_id !~ '^[A-Za-z0-9._:-]{1,120}$'
     OR p_lease_duration_ms <= 15000
     OR p_lease_duration_ms > 120000
  THEN
    RAISE EXCEPTION 'invalid batch claim input' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO batch_row
    FROM public.process_refresh_batch
   WHERE id = p_batch_id
   FOR UPDATE;
  IF batch_row.id IS NULL OR batch_row.status IN ('completed', 'completed_with_issues', 'cancelled') THEN
    RETURN;
  END IF;

  PERFORM set_config('juridico.phase9_internal', '1', true);
  SELECT j.* INTO job_row
    FROM public.query_job j
   WHERE j.office_id = batch_row.office_id
     AND j.batch_id = batch_row.id
     AND j.status IN ('pending', 'retry_scheduled')
     AND j.available_at <= clock_timestamp()
     AND j.attempt_count < j.max_attempts
   ORDER BY j.available_at, j.created_at, j.id
   LIMIT 1
   FOR UPDATE SKIP LOCKED;

  IF job_row.id IS NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.query_job qj
       WHERE qj.office_id = batch_row.office_id
         AND qj.batch_id = batch_row.id
         AND qj.status IN ('pending', 'retry_scheduled', 'running')
    ) THEN
      UPDATE public.process_refresh_batch
         SET status = CASE
           WHEN EXISTS (
             SELECT 1 FROM public.query_job qj
              WHERE qj.office_id = batch_row.office_id
                AND qj.batch_id = batch_row.id
                AND qj.status IN ('terminal_failure')
           ) THEN 'completed_with_issues'
           ELSE 'completed'
         END,
         finished_at = coalesce(finished_at, clock_timestamp()),
         updated_at = clock_timestamp()
       WHERE id = batch_row.id;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO process_row
    FROM public.legal_process lp
   WHERE lp.id = job_row.process_id
     AND lp.office_id = job_row.office_id
   FOR SHARE;
  IF process_row.id IS NULL OR process_row.status <> 'active'
     OR process_row.is_public IS DISTINCT FROM true
  THEN
    UPDATE public.query_job
       SET status = 'terminal_failure',
           last_error_code = 'process_not_eligible',
           last_error_message = 'Processo não elegível para atualização.',
           finished_at = clock_timestamp(),
           updated_at = clock_timestamp(),
           available_at = clock_timestamp()
     WHERE id = job_row.id;
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
  UPDATE public.process_refresh_batch
     SET status = 'running',
         started_at = coalesce(started_at, clock_timestamp()),
         updated_at = clock_timestamp()
   WHERE id = batch_row.id;

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

REVOKE ALL ON FUNCTION public.realignment1_claim_client_portfolio_job(UUID, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.realignment1_claim_client_portfolio_job(UUID, TEXT, INTEGER)
  TO service_role;

-- Read model da carteira: somente dados resumidos. O histórico completo é
-- carregado por get_client_portfolio_process_detail sob demanda.
CREATE OR REPLACE FUNCTION public.get_client_portfolio_read_model(
  p_client_id UUID DEFAULT NULL
)
RETURNS SETOF JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
WITH visible_clients AS (
  SELECT c.id AS client_id, c.office_id, p.display_name AS client_name
    FROM public.client c
    JOIN public.party p
      ON p.id = c.party_id
     AND p.office_id = c.office_id
   WHERE c.status = 'active'
     AND (p_client_id IS NULL OR c.id = p_client_id)
), client_processes AS (
  SELECT
    lp.id AS process_id,
    lp.office_id,
    lp.client_id,
    lp.cnj_number,
    lp.tribunal,
    lp.system,
    lp.is_public,
    lp.status,
    lp.responsible_user_id,
    lp.next_action,
    lp.created_at
  FROM public.legal_process lp
  JOIN visible_clients vc ON vc.client_id = lp.client_id
), latest_job AS (
  SELECT DISTINCT ON (qj.process_id)
    qj.process_id, qj.status, qj.last_error_code, qj.created_at
    FROM public.query_job qj
    JOIN client_processes cp ON cp.process_id = qj.process_id
   ORDER BY qj.process_id, qj.created_at DESC, qj.id DESC
), latest_execution AS (
  SELECT DISTINCT ON (qe.process_id)
    qe.id, qe.process_id, qe.status, qe.error_code,
    qe.finished_at, qe.started_at
    FROM public.query_execution qe
    JOIN client_processes cp ON cp.process_id = qe.process_id
   WHERE qe.finished_at IS NOT NULL
   ORDER BY qe.process_id, qe.finished_at DESC, qe.id DESC
), latest_exchange AS (
  SELECT DISTINCT ON (pe.process_id)
    pe.id, pe.process_id, pe.result_kind, pe.result_status,
    pe.error_code, pe.created_at
    FROM public.provider_exchange pe
    JOIN client_processes cp ON cp.process_id = pe.process_id
   ORDER BY pe.process_id, pe.created_at DESC, pe.id DESC
), latest_observation AS (
  SELECT DISTINCT ON (pe.process_id)
    pe.id, pe.process_id, pe.normalized_result, pe.created_at
    FROM public.provider_exchange pe
    JOIN client_processes cp ON cp.process_id = pe.process_id
   WHERE pe.result_kind = 'observation'
     AND pe.result_status = 'observed'
   ORDER BY pe.process_id, pe.created_at DESC, pe.id DESC
), latest_comparison AS (
  SELECT DISTINCT ON (pc.process_id)
    pc.id, pc.process_id, pc.result, pc.reason_code, pc.normalized_diff,
    pc.created_at, current_snapshot.created_at AS snapshot_created_at
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
    coalesce(movement->>'type', movement->>'description') AS movement_type,
    movement->>'code' AS movement_code,
    movement->>'description' AS movement_description,
    movement->'court'->>'name' AS movement_court
    FROM latest_observation lo
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(lo.normalized_result->'data'->'movements') = 'array'
        THEN lo.normalized_result->'data'->'movements'
        ELSE '[]'::jsonb END
    ) AS movement
   WHERE movement->>'date' IS NOT NULL
   ORDER BY lo.process_id, movement->>'date' DESC, movement->>'movementRef' DESC
), process_states AS (
  SELECT
    cp.*,
    up.name AS responsible_name,
    le.finished_at AS last_consulted_at,
    lo.normalized_result->'sourceMetadata'->>'sourceUpdatedAt' AS source_updated_at,
    lo.normalized_result->'data'->'basicData' AS basic_data,
    rm.movement_date,
    rm.movement_type,
    rm.movement_code,
    rm.movement_description,
    rm.movement_court,
    CASE
      WHEN lj.status IN ('pending', 'running') THEN 'updating'
      WHEN lx.result_status = 'manual_review_required'
        OR lx.error_code IN ('datajud_multiple_hits_returned', 'datajud_movement_ambiguity_detected')
        THEN 'manual_review'
      WHEN lj.status IN ('retry_scheduled', 'terminal_failure')
        OR le.status IN ('retry_scheduled', 'terminal_failure')
        OR lx.result_kind = 'failure' THEN 'failure'
      WHEN le.id IS NULL OR lo.id IS NULL THEN 'not_consulted'
      WHEN lc.result = 'not_comparable' AND lc.reason_code = 'first_snapshot' THEN 'first_observation'
      WHEN lc.result = 'changed' THEN 'changed'
      WHEN lc.result = 'unchanged' THEN 'unchanged'
      ELSE 'first_observation'
    END AS state,
    CASE
      WHEN lc.result = 'changed' THEN (
        SELECT count(*)::INTEGER
          FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(lc.normalized_diff->'entries') = 'array'
              THEN lc.normalized_diff->'entries' ELSE '[]'::jsonb END
          ) AS entry
         WHERE entry->>'changeType' = 'movement_added'
      )
      WHEN lc.result = 'not_comparable' AND lc.reason_code = 'first_snapshot' THEN
        jsonb_array_length(
          CASE WHEN jsonb_typeof(lo.normalized_result->'data'->'movements') = 'array'
            THEN lo.normalized_result->'data'->'movements' ELSE '[]'::jsonb END
        )
      ELSE 0
    END AS new_movement_count
  FROM client_processes cp
  LEFT JOIN public.user_profile up
    ON up.id = cp.responsible_user_id
   AND up.office_id = cp.office_id
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
    count(ps.process_id) FILTER (WHERE ps.state = 'changed')::INTEGER AS novelty_count,
    count(ps.process_id) FILTER (WHERE ps.state = 'not_consulted')::INTEGER AS not_updated_count,
    count(ps.process_id) FILTER (WHERE ps.state = 'failure')::INTEGER AS failure_count,
    count(ps.process_id) FILTER (WHERE ps.state = 'manual_review')::INTEGER AS review_count,
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
          'sourceStatus', NULL,
          'state', ps.state,
          'monitoringState', ps.state,
          'processClass', ps.basic_data->'processClass'->>'name',
          'degree', ps.basic_data->>'degree',
          'court', ps.basic_data->'court'->>'name',
          'filingDate', ps.basic_data->>'filingDate',
          'secrecyLevel', ps.basic_data->>'secrecyLevel',
          'system', coalesce(ps.basic_data->'system'->>'name', ps.system),
          'lastConsultedAt', ps.last_consulted_at,
          'sourceUpdatedAt', ps.source_updated_at,
          'lastMovement', CASE WHEN ps.movement_date IS NULL THEN NULL ELSE jsonb_build_object(
            'date', ps.movement_date,
            'code', ps.movement_code,
            'type', ps.movement_type,
            'description', ps.movement_description,
            'court', ps.movement_court
          ) END,
          'hasNews', ps.state = 'changed',
          'newMovementCount', ps.new_movement_count,
          'responsibleName', ps.responsible_name,
          'nextAction', ps.next_action
        ) ORDER BY ps.created_at DESC, ps.process_id
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

CREATE OR REPLACE FUNCTION public.get_client_portfolio_process_detail(
  p_process_id UUID
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path = pg_catalog, public
AS $$
WITH portfolio_process AS (
  SELECT process
    FROM public.get_client_portfolio_read_model(NULL) portfolio
    CROSS JOIN LATERAL jsonb_array_elements(portfolio->'processes') AS process
   WHERE process->>'processId' = p_process_id::TEXT
), process_source AS (
  SELECT pe.normalized_result->'data' AS data
    FROM public.provider_exchange pe
    JOIN public.legal_process lp
      ON lp.office_id = pe.office_id
     AND lp.id = pe.process_id
   WHERE lp.id = p_process_id
     AND pe.result_kind = 'observation'
     AND pe.result_status = 'observed'
   ORDER BY pe.created_at DESC, pe.id DESC
   LIMIT 1
), manual_parties AS (
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('name', p.display_name, 'role', pp.role_in_process)
      ORDER BY p.display_name, pp.id),
    '[]'::jsonb
  ) AS parties
    FROM public.process_party pp
    JOIN public.party p
      ON p.office_id = pp.office_id
     AND p.id = pp.party_id
   WHERE pp.process_id = p_process_id
     AND pp.status = 'active'
), source_movements AS (
  SELECT coalesce(
    jsonb_agg(jsonb_build_object(
      'date', movement->>'date',
      'code', movement->>'code',
      'type', coalesce(movement->>'type', movement->>'description'),
      'description', movement->>'description',
      'court', movement->'court'->>'name',
      'complements', coalesce(movement->'complements', '[]'::jsonb)
    ) ORDER BY movement->>'date' DESC, movement->>'movementRef' DESC),
    '[]'::jsonb
  ) AS movements
    FROM process_source ps
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(ps.data->'movements') = 'array'
        THEN ps.data->'movements' ELSE '[]'::jsonb END
    ) AS movement
)
SELECT CASE WHEN pp.process IS NULL THEN NULL::JSONB ELSE
  pp.process || jsonb_build_object(
    'filingDate', ps.data->'basicData'->>'filingDate',
    'secrecyLevel', ps.data->'basicData'->>'secrecyLevel',
    'system', coalesce(ps.data->'basicData'->'system'->>'name', pp.process->>'system'),
    'subjects', coalesce(
      (SELECT jsonb_agg(subject->>'name' ORDER BY subject->>'code')
         FROM jsonb_array_elements(
           CASE WHEN jsonb_typeof(ps.data->'basicData'->'subjects') = 'array'
             THEN ps.data->'basicData'->'subjects' ELSE '[]'::jsonb END
         ) AS subject),
      '[]'::jsonb
    ),
    'parties', mp.parties,
    'movements', sm.movements
  )
END
FROM portfolio_process pp
LEFT JOIN process_source ps ON true
LEFT JOIN manual_parties mp ON true
LEFT JOIN source_movements sm ON true;
$$;

REVOKE ALL ON FUNCTION public.get_client_portfolio_process_detail(UUID)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_client_portfolio_process_detail(UUID)
  TO authenticated;

COMMENT ON TABLE public.process_refresh_batch IS
  'Lote assíncrono de atualizações individuais da carteira conhecida do cliente.';
COMMENT ON FUNCTION public.realignment1_request_client_portfolio_refresh(UUID) IS
  'Solicita atualização dos processos públicos e ativos de um cliente sob RLS/ator ativo.';
COMMENT ON FUNCTION public.realignment1_claim_client_portfolio_job(UUID, TEXT, INTEGER) IS
  'Claim backend-only de um job pertencente a um lote específico.';
