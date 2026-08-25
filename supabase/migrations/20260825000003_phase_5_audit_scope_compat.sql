-- Phase 5 audit validator scope compatibility.
CREATE OR REPLACE FUNCTION public.phase5_validate_audit_row() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  phase5_actions constant text[] := ARRAY['client.created','client.updated','client.deactivated','party.created','party.updated','party.deactivated','client_related_party.created','client_related_party.updated','client_related_party.confirmed','client_related_party.rejected','client_related_party.deactivated'];
  allowed_metadata constant text[] := ARRAY['before','after'];
  key_name text;
BEGIN
  IF NOT (NEW.action = ANY (phase5_actions)) THEN RETURN NEW; END IF;
  IF NEW.audit_scope IS DISTINCT FROM 'operational' THEN RAISE EXCEPTION 'phase 5 audit events require operational scope' USING errcode='22023'; END IF;
  IF (NEW.action LIKE 'client.%' AND NEW.entity_type IS DISTINCT FROM 'client') OR (NEW.action LIKE 'party.%' AND NEW.entity_type IS DISTINCT FROM 'party') OR (NEW.action LIKE 'client_related_party.%' AND NEW.entity_type IS DISTINCT FROM 'client_related_party') THEN RAISE EXCEPTION 'phase 5 audit action/entity mismatch' USING errcode='22023'; END IF;
  IF NEW.office_id IS NULL OR NEW.actor_user_id IS NULL THEN RAISE EXCEPTION 'phase 5 audit actor and office are required' USING errcode='23514'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_profile up JOIN public.office o ON o.id=up.office_id WHERE up.id=NEW.actor_user_id AND up.office_id=NEW.office_id AND up.is_active=true AND o.is_active=true) THEN RAISE EXCEPTION 'phase 5 audit actor or office is inactive/invalid' USING errcode='23514'; END IF;
  IF NEW.metadata IS NULL OR jsonb_typeof(NEW.metadata) <> 'object' THEN RAISE EXCEPTION 'invalid phase 5 audit metadata' USING errcode='22023'; END IF;
  FOR key_name IN SELECT jsonb_object_keys(NEW.metadata) LOOP IF NOT (key_name = ANY (allowed_metadata)) THEN RAISE EXCEPTION 'invalid phase 5 audit metadata key' USING errcode='22023'; END IF; END LOOP;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS phase5_validate_audit_row ON public.audit_log;
CREATE TRIGGER phase5_validate_audit_row BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.phase5_validate_audit_row();
REVOKE ALL ON FUNCTION public.phase5_validate_audit_row() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.phase5_validate_audit_row() IS 'Validates only Phase 5 operational audit actions; administrative 4C actions pass through.';

-- RLS policies execute this SECURITY DEFINER helper on behalf of authenticated users.
GRANT EXECUTE ON FUNCTION public.can_view_operational_row(uuid) TO authenticated;

