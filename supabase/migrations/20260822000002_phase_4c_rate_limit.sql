-- Migration: 20260822000002_phase_4c_rate_limit
-- Descrição: Rate limit administrativo persistente e atômico no PostgreSQL.

CREATE TABLE public.rate_limit_bucket (
    operation TEXT NOT NULL CHECK (operation IN (
        'admin.invite',
        'admin.change_role',
        'admin.set_active',
        'admin.set_owner',
        'admin.update_office_name',
        'admin.audit_export'
    )),
    office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
    actor_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    window_started_at TIMESTAMPTZ NOT NULL,
    request_count INTEGER NOT NULL CHECK (request_count >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (operation, office_id, actor_user_id)
);

ALTER TABLE public.rate_limit_bucket ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rate_limit_bucket FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.rate_limit_bucket TO service_role;

CREATE OR REPLACE FUNCTION public.consume_admin_rate_limit(
    p_operation TEXT
)
RETURNS TABLE (
    allowed BOOLEAN,
    retry_after_seconds INTEGER,
    current_count INTEGER,
    limit_count INTEGER,
    window_seconds INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    bucket public.rate_limit_bucket%ROWTYPE;
    current_time_utc TIMESTAMPTZ := clock_timestamp();
    window_end TIMESTAMPTZ;
BEGIN
    SELECT * INTO actor FROM public.require_active_actor();
    IF p_operation <> 'admin.audit_export'
       AND actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;
    IF p_operation = 'admin.audit_export'
       AND actor.actor_role <> 'auditor'
       AND actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    CASE p_operation
        WHEN 'admin.invite' THEN
            limit_count := 5;
            window_seconds := 900;
        WHEN 'admin.change_role' THEN
            limit_count := 20;
            window_seconds := 900;
        WHEN 'admin.set_active' THEN
            limit_count := 20;
            window_seconds := 900;
        WHEN 'admin.set_owner' THEN
            limit_count := 10;
            window_seconds := 900;
        WHEN 'admin.update_office_name' THEN
            limit_count := 10;
            window_seconds := 900;
        WHEN 'admin.audit_export' THEN
            limit_count := 3;
            window_seconds := 3600;
        ELSE
            RAISE EXCEPTION 'rate limit operation is not allowlisted' USING ERRCODE = '22023';
    END CASE;

    INSERT INTO public.rate_limit_bucket (
        operation,
        office_id,
        actor_user_id,
        window_started_at,
        request_count,
        updated_at
    ) VALUES (
        p_operation,
        actor.actor_office_id,
        actor.actor_id,
        current_time_utc,
        0,
        current_time_utc
    )
    ON CONFLICT (operation, office_id, actor_user_id) DO NOTHING;

    SELECT * INTO bucket
      FROM public.rate_limit_bucket
     WHERE operation = p_operation
       AND office_id = actor.actor_office_id
       AND actor_user_id = actor.actor_id
     FOR UPDATE;

    window_end := bucket.window_started_at + make_interval(secs => window_seconds);
    IF current_time_utc >= window_end THEN
        UPDATE public.rate_limit_bucket
           SET window_started_at = current_time_utc,
               request_count = 1,
               updated_at = current_time_utc
         WHERE operation = bucket.operation
           AND office_id = bucket.office_id
           AND actor_user_id = bucket.actor_user_id;
        allowed := true;
        current_count := 1;
        retry_after_seconds := 0;
    ELSIF bucket.request_count < limit_count THEN
        UPDATE public.rate_limit_bucket
           SET request_count = bucket.request_count + 1,
               updated_at = current_time_utc
         WHERE operation = bucket.operation
           AND office_id = bucket.office_id
           AND actor_user_id = bucket.actor_user_id;
        allowed := true;
        current_count := bucket.request_count + 1;
        retry_after_seconds := 0;
    ELSE
        allowed := false;
        current_count := bucket.request_count;
        retry_after_seconds := GREATEST(
            1,
            CEIL(EXTRACT(EPOCH FROM (window_end - current_time_utc)))::INTEGER
        );
    END IF;

    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_admin_rate_limit(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_admin_rate_limit(TEXT) TO authenticated;
