-- Migration incremental para endurecer a integridade da auditoria 4C

-- 1. Substituir a gravação pública de convite por uma função interna
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
    action_name TEXT;
    meta JSONB := '{}'::jsonb;
BEGIN
    -- Valida o actor (deve ser ativo, owner, em office ativo)
    SELECT * INTO actor FROM public.user_profile
     WHERE id = p_actor_user_id
       AND is_active = true
       AND is_owner = true;
       
    IF actor.id IS NULL THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;
    
    -- Verifica o office
    IF NOT EXISTS (SELECT 1 FROM public.office WHERE id = actor.office_id AND is_active = true) THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF p_outcome NOT IN ('accepted', 'rejected') THEN
        RAISE EXCEPTION 'invalid invite outcome' USING ERRCODE = '22023';
    END IF;

    -- Valida target
    IF p_target_user_id IS NOT NULL THEN
        SELECT * INTO target FROM public.user_profile WHERE id = p_target_user_id;
        IF target.id IS NULL OR target.office_id <> actor.office_id THEN
            RAISE EXCEPTION 'invalid target user' USING ERRCODE = '22023';
        END IF;
    END IF;

    IF p_reason IS NOT NULL THEN
        meta := jsonb_build_object('reason', p_reason);
    END IF;

    action_name := 'invite.' || p_outcome;
    
    -- Usa o mesmo insert interno para garantir consistência
    RETURN public.write_admin_audit(
        action_name,
        'user_profile',
        p_target_user_id,
        meta
    );
END;
$$;

-- 2. Operação real combinada de exportação
CREATE OR REPLACE FUNCTION public.export_administrative_audit(
    p_limit INTEGER DEFAULT 50,
    p_action TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL
)
RETURNS SETOF public.audit_log
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    actor RECORD;
    rate_limit_result RECORD;
    effective_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 1000);
BEGIN
    SELECT * INTO actor FROM public.require_active_actor();
    IF actor.actor_role <> 'auditor' AND actor.actor_is_owner IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    -- Consome o bucket na mesma transação
    SELECT * INTO rate_limit_result FROM public.consume_admin_rate_limit('admin.audit_export');
    IF rate_limit_result.allowed IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'rate limit exceeded' USING ERRCODE = '42900';
    END IF;

    -- Registra a exportação
    PERFORM public.write_admin_audit(
        'audit.export',
        'audit_log',
        NULL,
        jsonb_build_object('reason', 'csv')
    );

    -- Retorna os dados autorizados
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

-- 3. Função interna para registro de rejeições
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
BEGIN
    -- Valida o actor
    SELECT * INTO actor FROM public.user_profile
     WHERE id = p_actor_user_id
       AND is_active = true
       AND is_owner = true;
       
    IF actor.id IS NULL THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;
    
    -- Verifica o office
    IF NOT EXISTS (SELECT 1 FROM public.office WHERE id = actor.office_id AND is_active = true) THEN
        RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
    END IF;

    IF p_action NOT IN ('last_owner_blocked') THEN
        RAISE EXCEPTION 'invalid rejection action' USING ERRCODE = '22023';
    END IF;
    
    IF p_reason IS NULL THEN
        RAISE EXCEPTION 'reason is required' USING ERRCODE = '22023';
    END IF;

    -- Valida target (deve estar no mesmo office)
    IF p_entity_id IS NOT NULL AND p_entity_type = 'user_profile' THEN
        SELECT * INTO target FROM public.user_profile WHERE id = p_entity_id;
        IF target.id IS NULL OR target.office_id <> actor.office_id THEN
            RAISE EXCEPTION 'invalid target entity' USING ERRCODE = '22023';
        END IF;
    END IF;

    RETURN public.write_admin_audit(
        p_action,
        p_entity_type,
        p_entity_id,
        jsonb_build_object('reason', p_reason)
    );
END;
$$;

-- 4. Ajustar privilégios
-- Revogar as funções antigas
REVOKE ALL ON FUNCTION public.record_invite_audit(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_audit_export() FROM PUBLIC, anon, authenticated;
DROP FUNCTION IF EXISTS public.record_invite_audit(UUID, TEXT);
DROP FUNCTION IF EXISTS public.record_audit_export();

-- Revogar funções internas de todos
REVOKE ALL ON FUNCTION public.record_invite_audit_internal(UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_rejection_audit_internal(UUID, TEXT, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- Conceder execução apenas para service_role nas funções internas
GRANT EXECUTE ON FUNCTION public.record_invite_audit_internal(UUID, UUID, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_rejection_audit_internal(UUID, TEXT, TEXT, UUID, TEXT) TO service_role;

-- Conceder execução da exportação combinada para authenticated
REVOKE ALL ON FUNCTION public.export_administrative_audit(INTEGER, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_administrative_audit(INTEGER, TEXT, TEXT) TO authenticated;
