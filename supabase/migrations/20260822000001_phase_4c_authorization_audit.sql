-- Migration: 20260822000001_phase_4c_authorization_audit
-- Descrição: Hardening do control plane, RPCs administrativas e auditoria append-only.

-- 1. Remover o caminho genérico de mutação das chaves públicas.
REVOKE INSERT, UPDATE, DELETE ON public.user_profile FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.office FROM authenticated;
DROP POLICY IF EXISTS "Owners can update profiles in their office" ON public.user_profile;
DROP POLICY IF EXISTS "Owners can update their office" ON public.office;

-- 2. Auditoria administrativa separada da auditoria operacional.
CREATE TABLE public.audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    audit_scope TEXT NOT NULL CHECK (audit_scope IN ('administrative', 'operational')),
    office_id UUID NOT NULL REFERENCES public.office(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL CHECK (length(action) BETWEEN 1 AND 80),
    entity_type TEXT NOT NULL CHECK (length(entity_type) BETWEEN 1 AND 80),
    entity_id UUID,
    correlation_id UUID NOT NULL DEFAULT gen_random_uuid(),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_log_office_created_at
    ON public.audit_log (office_id, created_at DESC);
CREATE INDEX idx_audit_log_actor_created_at
    ON public.audit_log (actor_user_id, created_at DESC);
CREATE INDEX idx_audit_log_action_created_at
    ON public.audit_log (action, created_at DESC);
CREATE INDEX idx_audit_log_entity
    ON public.audit_log (entity_type, entity_id);
CREATE INDEX idx_audit_log_correlation_id
    ON public.audit_log (correlation_id);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.audit_log FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.audit_log TO authenticated;
GRANT SELECT ON public.audit_log TO service_role;

CREATE OR REPLACE FUNCTION public.prevent_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only' USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER tr_audit_log_append_only
BEFORE UPDATE OR DELETE ON public.audit_log
FOR EACH ROW
EXECUTE FUNCTION public.prevent_audit_mutation();

-- 3. Contexto confiável do ator. Nunca recebe office/actor/role pelo cliente.
CREATE OR REPLACE FUNCTION public.require_active_actor()
RETURNS TABLE (
    actor_id UUID,
    actor_office_id UUID,
    actor_role public.user_role,
    actor_is_owner BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    SELECT up.id, up.office_id, up.role, up.is_owner
      INTO actor_id, actor_office_id, actor_role, actor_is_owner
      FROM public.user_profile up
      JOIN public.office o ON o.id = up.office_id
     WHERE up.id = auth.uid()
       AND up.is_active = true
       AND o.is_active = true;

    IF actor_id IS NULL THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_active_owner()
RETURNS TABLE (
    actor_id UUID,
    actor_office_id UUID,
    actor_role public.user_role,
    actor_is_owner BOOLEAN
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
    IF actor.actor_id IS NULL OR actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    actor_id := actor.actor_id;
    actor_office_id := actor.actor_office_id;
    actor_role := actor.actor_role;
    actor_is_owner := actor.actor_is_owner;
    RETURN NEXT;
END;
$$;

-- 4. Escrita interna e validada de auditoria. Não recebe actor/office.
CREATE OR REPLACE FUNCTION public.write_admin_audit(
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
    before_value JSONB;
    after_value JSONB;
BEGIN
    SELECT * INTO actor FROM public.require_active_actor();
    IF p_action <> 'audit.export'
       AND actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;
    IF p_action = 'audit.export'
       AND actor.actor_role <> 'auditor'
       AND actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF p_action IS NULL OR p_entity_type IS NULL OR p_metadata IS NULL
       OR jsonb_typeof(p_metadata) <> 'object' THEN
        RAISE EXCEPTION 'invalid audit event' USING ERRCODE = '22023';
    END IF;

    IF p_action IN ('change_role', 'set_owner', 'set_active', 'office.rename') THEN
        IF NOT (p_metadata ? 'before') OR NOT (p_metadata ? 'after')
           OR EXISTS (
               SELECT 1
                 FROM jsonb_object_keys(p_metadata) AS keys(key)
                WHERE key NOT IN ('before', 'after')
           ) THEN
            RAISE EXCEPTION 'invalid audit metadata' USING ERRCODE = '22023';
        END IF;

        before_value := p_metadata->'before';
        after_value := p_metadata->'after';
        IF jsonb_typeof(before_value) <> 'object'
           OR jsonb_typeof(after_value) <> 'object' THEN
            RAISE EXCEPTION 'invalid audit metadata' USING ERRCODE = '22023';
        END IF;
    ELSIF p_action IN ('invite.accepted', 'invite.rejected', 'audit.export', 'last_owner_blocked') THEN
        IF EXISTS (
            SELECT 1
              FROM jsonb_object_keys(p_metadata) AS keys(key)
             WHERE key NOT IN ('reason')
        ) THEN
            RAISE EXCEPTION 'invalid audit metadata' USING ERRCODE = '22023';
        END IF;
    ELSE
        RAISE EXCEPTION 'audit action is not allowlisted' USING ERRCODE = '22023';
    END IF;

    IF p_action = 'change_role' AND (
        (before_value - 'role') <> '{}'::jsonb
        OR (after_value - 'role') <> '{}'::jsonb
        OR (before_value->>'role') NOT IN ('lawyer', 'operator', 'reviewer', 'auditor')
        OR (after_value->>'role') NOT IN ('lawyer', 'operator', 'reviewer', 'auditor')
    ) THEN
        RAISE EXCEPTION 'invalid audit metadata' USING ERRCODE = '22023';
    END IF;

    IF p_action = 'set_owner' AND (
        (before_value - 'is_owner') <> '{}'::jsonb
        OR (after_value - 'is_owner') <> '{}'::jsonb
        OR (before_value->>'is_owner') NOT IN ('true', 'false')
        OR (after_value->>'is_owner') NOT IN ('true', 'false')
    ) THEN
        RAISE EXCEPTION 'invalid audit metadata' USING ERRCODE = '22023';
    END IF;

    IF p_action = 'set_active' AND (
        (before_value - 'is_active') <> '{}'::jsonb
        OR (after_value - 'is_active') <> '{}'::jsonb
        OR (before_value->>'is_active') NOT IN ('true', 'false')
        OR (after_value->>'is_active') NOT IN ('true', 'false')
    ) THEN
        RAISE EXCEPTION 'invalid audit metadata' USING ERRCODE = '22023';
    END IF;

    IF p_action = 'office.rename' AND (
        (before_value - 'name') <> '{}'::jsonb
        OR (after_value - 'name') <> '{}'::jsonb
        OR before_value->>'name' IS NULL
        OR after_value->>'name' IS NULL
    ) THEN
        RAISE EXCEPTION 'invalid audit metadata' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.audit_log (
        audit_scope,
        office_id,
        actor_user_id,
        action,
        entity_type,
        entity_id,
        metadata
    ) VALUES (
        'administrative',
        actor.actor_office_id,
        actor.actor_id,
        p_action,
        p_entity_type,
        p_entity_id,
        p_metadata
    )
    RETURNING id INTO audit_id;

    RETURN audit_id;
END;
$$;

-- 5. RPCs administrativas: cada uma deriva actor/office no banco e trava o alvo.
CREATE OR REPLACE FUNCTION public.change_user_role(
    p_target_user_id UUID,
    p_new_role public.user_role
)
RETURNS public.user_profile
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    target public.user_profile%ROWTYPE;
    updated_profile public.user_profile%ROWTYPE;
BEGIN
    SELECT * INTO actor FROM public.require_active_owner();
    IF p_target_user_id = actor.actor_id THEN
        RAISE EXCEPTION 'cannot change own role' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO target
      FROM public.user_profile
     WHERE id = p_target_user_id
       AND office_id = actor.actor_office_id
     FOR UPDATE;
    IF target.id IS NULL THEN
        RAISE EXCEPTION 'target not found' USING ERRCODE = 'P0002';
    END IF;

    IF target.role IS NOT DISTINCT FROM p_new_role THEN
        RETURN target;
    END IF;

    UPDATE public.user_profile
       SET role = p_new_role
     WHERE id = target.id
    RETURNING * INTO updated_profile;

    PERFORM public.write_admin_audit(
        'change_role',
        'user_profile',
        target.id,
        jsonb_build_object(
            'before', jsonb_build_object('role', target.role::text),
            'after', jsonb_build_object('role', updated_profile.role::text)
        )
    );

    RETURN updated_profile;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_user_active(
    p_target_user_id UUID,
    p_is_active BOOLEAN
)
RETURNS public.user_profile
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    target public.user_profile%ROWTYPE;
    updated_profile public.user_profile%ROWTYPE;
BEGIN
    SELECT * INTO actor FROM public.require_active_owner();

    SELECT * INTO target
      FROM public.user_profile
     WHERE id = p_target_user_id
       AND office_id = actor.actor_office_id
     FOR UPDATE;
    IF target.id IS NULL THEN
        RAISE EXCEPTION 'target not found' USING ERRCODE = 'P0002';
    END IF;

    IF target.is_active IS NOT DISTINCT FROM p_is_active THEN
        RETURN target;
    END IF;

    UPDATE public.user_profile
       SET is_active = p_is_active
     WHERE id = target.id
    RETURNING * INTO updated_profile;

    PERFORM public.write_admin_audit(
        'set_active',
        'user_profile',
        target.id,
        jsonb_build_object(
            'before', jsonb_build_object('is_active', target.is_active),
            'after', jsonb_build_object('is_active', updated_profile.is_active)
        )
    );

    RETURN updated_profile;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_user_owner(
    p_target_user_id UUID,
    p_is_owner BOOLEAN
)
RETURNS public.user_profile
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    target public.user_profile%ROWTYPE;
    updated_profile public.user_profile%ROWTYPE;
BEGIN
    SELECT * INTO actor FROM public.require_active_owner();
    IF p_target_user_id = actor.actor_id THEN
        RAISE EXCEPTION 'cannot change own owner status' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO target
      FROM public.user_profile
     WHERE id = p_target_user_id
       AND office_id = actor.actor_office_id
     FOR UPDATE;
    IF target.id IS NULL THEN
        RAISE EXCEPTION 'target not found' USING ERRCODE = 'P0002';
    END IF;

    IF target.is_owner IS NOT DISTINCT FROM p_is_owner THEN
        RETURN target;
    END IF;

    UPDATE public.user_profile
       SET is_owner = p_is_owner
     WHERE id = target.id
    RETURNING * INTO updated_profile;

    PERFORM public.write_admin_audit(
        'set_owner',
        'user_profile',
        target.id,
        jsonb_build_object(
            'before', jsonb_build_object('is_owner', target.is_owner),
            'after', jsonb_build_object('is_owner', updated_profile.is_owner)
        )
    );

    RETURN updated_profile;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_office_name(
    p_name TEXT
)
RETURNS public.office
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    current_office public.office%ROWTYPE;
    updated_office public.office%ROWTYPE;
    normalized_name TEXT := btrim(p_name);
BEGIN
    SELECT * INTO actor FROM public.require_active_owner();
    IF normalized_name IS NULL OR length(normalized_name) < 2 OR length(normalized_name) > 160 THEN
        RAISE EXCEPTION 'invalid office name' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO current_office
      FROM public.office
     WHERE id = actor.actor_office_id
     FOR UPDATE;
    IF current_office.id IS NULL OR current_office.is_active IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF current_office.name = normalized_name THEN
        RETURN current_office;
    END IF;

    UPDATE public.office
       SET name = normalized_name
     WHERE id = current_office.id
    RETURNING * INTO updated_office;

    PERFORM public.write_admin_audit(
        'office.rename',
        'office',
        current_office.id,
        jsonb_build_object(
            'before', jsonb_build_object('name', current_office.name),
            'after', jsonb_build_object('name', updated_office.name)
        )
    );

    RETURN updated_office;
END;
$$;

-- 6. Auditoria administrativa: leitura derivada do office do actor.
CREATE OR REPLACE FUNCTION public.get_administrative_audit(
    p_limit INTEGER DEFAULT 50,
    p_action TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL
)
RETURNS SETOF public.audit_log
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    effective_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
BEGIN
    SELECT * INTO actor FROM public.require_active_actor();
    IF actor.actor_role <> 'auditor' AND actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT al.*
      FROM public.audit_log al
     WHERE al.audit_scope = 'administrative'
       AND al.office_id = actor.actor_office_id
       AND (p_action IS NULL OR al.action = p_action)
       AND (p_entity_type IS NULL OR al.entity_type = p_entity_type)
     ORDER BY al.created_at DESC, al.id DESC
     LIMIT effective_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_invite_audit(
    p_target_user_id UUID,
    p_outcome TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    action_name TEXT;
BEGIN
    IF p_outcome NOT IN ('accepted', 'rejected') THEN
        RAISE EXCEPTION 'invalid invite outcome' USING ERRCODE = '22023';
    END IF;

    action_name := 'invite.' || p_outcome;
    RETURN public.write_admin_audit(
        action_name,
        'user_profile',
        p_target_user_id,
        '{}'::jsonb
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_audit_export()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
BEGIN
    SELECT * INTO actor FROM public.require_active_actor();
    IF actor.actor_role <> 'auditor'
       AND actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    RETURN public.write_admin_audit(
        'audit.export',
        'audit_log',
        NULL,
        jsonb_build_object('reason', 'csv')
    );
END;
$$;

-- 7. Privilégios mínimos. Funções de contexto/escrita permanecem internas.
REVOKE ALL ON FUNCTION public.prevent_audit_mutation() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prevent_audit_mutation() TO service_role;
REVOKE ALL ON FUNCTION public.require_active_actor() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.require_active_owner() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.write_admin_audit(TEXT, TEXT, UUID, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.change_user_role(UUID, public.user_role) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_user_active(UUID, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_user_owner(UUID, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_office_name(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_administrative_audit(INTEGER, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_invite_audit(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_audit_export() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_user_role(UUID, public.user_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_user_active(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_user_owner(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_office_name(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_administrative_audit(INTEGER, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_invite_audit(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_audit_export() TO authenticated;
