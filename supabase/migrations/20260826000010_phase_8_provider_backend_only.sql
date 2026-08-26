SET lock_timeout = '2s';

-- A migration publicada da Fase 8 permanece imutável. Estes wrappers fecham a
-- fronteira PostgREST sem aceitar resultado, payload ou identidade do browser.
CREATE OR REPLACE FUNCTION public.require_provider_actor(p_actor_user_id UUID)
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
   WHERE up.id = p_actor_user_id
     AND up.is_active = true
     AND o.is_active = true;

  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;

  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_provider_process_eligible_internal(
  p_actor_user_id UUID,
  p_process_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
BEGIN
  SELECT * INTO actor FROM public.require_provider_actor(p_actor_user_id);
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  PERFORM public.require_provider_process_eligible(p_process_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.record_provider_exchange_internal(
  p_actor_user_id UUID,
  p_process_id UUID,
  p_provider_id TEXT,
  p_source TEXT,
  p_contract_version INTEGER,
  p_subject_ref TEXT,
  p_correlation_id TEXT,
  p_request_fingerprint TEXT,
  p_result_kind TEXT,
  p_result_status TEXT,
  p_error_code TEXT DEFAULT NULL,
  p_normalized_result JSONB DEFAULT NULL,
  p_raw_payload JSONB DEFAULT NULL,
  p_sanitization_version TEXT DEFAULT NULL,
  p_received_at TIMESTAMPTZ DEFAULT now()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
BEGIN
  SELECT * INTO actor FROM public.require_provider_actor(p_actor_user_id);
  IF actor.actor_role NOT IN ('lawyer', 'operator') THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;

  -- A função publicada mantém todas as validações, atomicidade, idempotência,
  -- sanitização, hash, append-only e auditoria. O actor só chega aqui após a
  -- revalidação acima e é projetado para auth.uid() no escopo da transação.
  PERFORM set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  RETURN public.record_provider_exchange(
    p_process_id,
    p_provider_id,
    p_source,
    p_contract_version,
    p_subject_ref,
    p_correlation_id,
    p_request_fingerprint,
    p_result_kind,
    p_result_status,
    p_error_code,
    p_normalized_result,
    p_raw_payload,
    p_sanitization_version,
    p_received_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_provider_raw_payload_internal(
  p_actor_user_id UUID,
  p_exchange_id UUID
)
RETURNS TABLE (
  id UUID,
  provider_exchange_id UUID,
  office_id UUID,
  process_id UUID,
  provider_id TEXT,
  source TEXT,
  correlation_id TEXT,
  sanitization_version TEXT,
  payload JSONB,
  payload_hash TEXT,
  payload_bytes INTEGER,
  received_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  actor RECORD;
BEGIN
  SELECT * INTO actor FROM public.require_provider_actor(p_actor_user_id);
  IF actor.actor_role <> 'lawyer' THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  RETURN QUERY SELECT * FROM public.get_provider_raw_payload(p_exchange_id);
END;
$$;

-- As assinaturas antigas deixam de ser caminhos utilizáveis pelo PostgREST.
-- Mantê-las sem EXECUTE evita breaking change destrutivo e preserva rollback.
REVOKE ALL ON FUNCTION public.record_provider_exchange(
  UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_provider_raw_payload(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.require_provider_process_eligible(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.write_provider_audit(TEXT, TEXT, UUID, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.require_provider_actor(UUID)
  FROM PUBLIC, anon, authenticated, service_role;

-- Somente o role de backend privilegiado chama os wrappers. O wrapper deriva
-- novamente office/role/status pelo actor recebido e nunca aceita dados do browser
-- como autoridade. Os objetos de tabela seguem sem DML direto para service_role.
REVOKE ALL ON FUNCTION public.require_provider_process_eligible_internal(UUID, UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_provider_exchange_internal(
  UUID, UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_provider_raw_payload_internal(UUID, UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.require_provider_process_eligible_internal(UUID, UUID)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.record_provider_exchange_internal(
  UUID, UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, TEXT, TIMESTAMPTZ
) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_provider_raw_payload_internal(UUID, UUID)
  TO service_role;
