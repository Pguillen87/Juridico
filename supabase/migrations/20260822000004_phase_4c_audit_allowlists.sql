-- Migration incremental: allowlists fechadas das funções internas de auditoria 4C
-- Não altera migrations anteriores já aplicadas.

-- 1. record_invite_audit_internal endurecida
--    accepted : target obrigatório, existente, no mesmo office, reason NULL
--    rejected  : reason obrigatório e dentro da allowlist fechada, target opcional
CREATE OR REPLACE FUNCTION public.record_invite_audit_internal(
    p_actor_user_id UUID,
    p_target_user_id UUID,
    p_outcome TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    target public.user_profile%ROWTYPE;
    meta JSONB := '{}'::jsonb;
    audit_id BIGINT;
BEGIN
    -- Valida o actor (existe, ativo, owner); office derivado do actor
    SELECT * INTO actor FROM public.user_profile
     WHERE id = p_actor_user_id
       AND is_active = true
       AND is_owner = true;

    IF actor.id IS NULL THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.office WHERE id = actor.office_id AND is_active = true) THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF p_outcome = 'accepted' THEN
        -- accepted exige target existente no mesmo office e SEM reason
        IF p_target_user_id IS NULL THEN
            RAISE EXCEPTION 'accepted invite audit requires a target user' USING ERRCODE = '22023';
        END IF;
        SELECT * INTO target FROM public.user_profile WHERE id = p_target_user_id;
        IF target.id IS NULL OR target.office_id <> actor.office_id THEN
            RAISE EXCEPTION 'invalid target user' USING ERRCODE = '22023';
        END IF;
        IF p_reason IS NOT NULL THEN
            RAISE EXCEPTION 'accepted invite audit must not carry a reason' USING ERRCODE = '22023';
        END IF;
    ELSIF p_outcome = 'rejected' THEN
        -- rejected exige reason da allowlist fechada; target pode ser NULL
        IF p_reason IS NULL THEN
            RAISE EXCEPTION 'rejected invite audit requires a reason' USING ERRCODE = '22023';
        END IF;
        IF p_reason NOT IN ('auth_error', 'profile_error', 'audit_error') THEN
            RAISE EXCEPTION 'rejected invite audit reason is not allowlisted' USING ERRCODE = '22023';
        END IF;
        IF p_target_user_id IS NOT NULL THEN
            SELECT * INTO target FROM public.user_profile WHERE id = p_target_user_id;
            IF target.id IS NULL OR target.office_id <> actor.office_id THEN
                RAISE EXCEPTION 'invalid target user' USING ERRCODE = '22023';
            END IF;
        END IF;
    ELSE
        RAISE EXCEPTION 'invalid invite outcome' USING ERRCODE = '22023';
    END IF;

    IF p_reason IS NOT NULL THEN
        meta := jsonb_build_object('reason', p_reason);
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
        actor.office_id,
        actor.id,
        'invite.' || p_outcome,
        'user_profile',
        p_target_user_id,
        meta
    )
    RETURNING id INTO audit_id;

    RETURN audit_id;
END;
$$;

-- 2. record_rejection_audit_internal endurecida
--    action allowlist : last_owner_blocked
--    entity_type      : user_profile
--    reason allowlist : deactivate_last_active_owner | revoke_last_active_owner
CREATE OR REPLACE FUNCTION public.record_rejection_audit_internal(
    p_actor_user_id UUID,
    p_action TEXT,
    p_entity_type TEXT,
    p_entity_id UUID,
    p_reason TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    target public.user_profile%ROWTYPE;
    audit_id BIGINT;
BEGIN
    SELECT * INTO actor FROM public.user_profile
     WHERE id = p_actor_user_id
       AND is_active = true
       AND is_owner = true;

    IF actor.id IS NULL THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.office WHERE id = actor.office_id AND is_active = true) THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF p_action <> 'last_owner_blocked' THEN
        RAISE EXCEPTION 'invalid rejection action' USING ERRCODE = '22023';
    END IF;

    IF p_entity_type <> 'user_profile' THEN
        RAISE EXCEPTION 'invalid rejection entity type' USING ERRCODE = '22023';
    END IF;

    IF p_reason NOT IN ('deactivate_last_active_owner', 'revoke_last_active_owner') THEN
        RAISE EXCEPTION 'invalid rejection reason' USING ERRCODE = '22023';
    END IF;

    IF p_entity_id IS NULL THEN
        RAISE EXCEPTION 'rejection audit requires an entity id' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO target FROM public.user_profile WHERE id = p_entity_id;
    IF target.id IS NULL OR target.office_id <> actor.office_id THEN
        RAISE EXCEPTION 'invalid target entity' USING ERRCODE = '22023';
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
        actor.office_id,
        actor.id,
        p_action,
        p_entity_type,
        p_entity_id,
        jsonb_build_object('reason', p_reason)
    )
    RETURNING id INTO audit_id;

    RETURN audit_id;
END;
$$;

-- 3. Privilégios: EXECUTE somente para service_role; negado a PUBLIC/anon/authenticated
REVOKE ALL ON FUNCTION public.record_invite_audit_internal(UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_rejection_audit_internal(UUID, TEXT, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_invite_audit_internal(UUID, UUID, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_rejection_audit_internal(UUID, TEXT, TEXT, UUID, TEXT) TO service_role;
