-- Phase 5 hardening: RLS/D-022, controlled relation vocabulary and invariants
DO $$ DECLARE p record; BEGIN
  FOR p IN SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname='public' AND tablename IN ('party','client','client_related_party') LOOP
    EXECUTE format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.can_view_operational_row(p_office_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_office uuid; v_role text; v_user_active boolean; v_office_active boolean;
BEGIN
  SELECT up.office_id, up.role::text, up.is_active, o.is_active
    INTO v_office, v_role, v_user_active, v_office_active
    FROM public.user_profile up JOIN public.office o ON o.id=up.office_id
   WHERE up.id=auth.uid();
  RETURN coalesce(v_user_active,false) AND coalesce(v_office_active,false)
    AND v_role IN ('lawyer','operator','reviewer') AND v_office=p_office_id;
END; $$;
REVOKE ALL ON FUNCTION public.can_view_operational_row(uuid) FROM PUBLIC, anon, authenticated;

ALTER TABLE public.party ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_related_party ENABLE ROW LEVEL SECURITY;
CREATE POLICY phase5_party_select ON public.party FOR SELECT TO authenticated USING (public.can_view_operational_row(office_id));
CREATE POLICY phase5_client_select ON public.client FOR SELECT TO authenticated USING (public.can_view_operational_row(office_id));
CREATE POLICY phase5_relation_select ON public.client_related_party FOR SELECT TO authenticated USING (public.can_view_operational_row(office_id));
GRANT SELECT ON public.party, public.client, public.client_related_party TO authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.party, public.client, public.client_related_party FROM PUBLIC, anon, authenticated;

ALTER TABLE public.client_related_party DROP CONSTRAINT IF EXISTS client_related_party_relation_type_check;
ALTER TABLE public.client_related_party ADD CONSTRAINT client_related_party_relation_type_check CHECK (relation_type IN ('subsidiary','family_member','dependent','representative','other'));

CREATE OR REPLACE FUNCTION public.phase5_validate_audit_row() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE allowed text[] := ARRAY['before','after']; k text; BEGIN
  IF NEW.entity_type NOT IN ('party','client','client_related_party') THEN RAISE EXCEPTION 'invalid audit entity' USING errcode='22023'; END IF;
  IF NEW.action NOT IN ('party.created','party.updated','party.deactivated','client.created','client.updated','client.deactivated','client_related_party.created','client_related_party.confirmed','client_related_party.rejected','client_related_party.deactivated') THEN RAISE EXCEPTION 'invalid audit action' USING errcode='22023'; END IF;
  FOR k IN SELECT jsonb_object_keys(coalesce(NEW.metadata,'{}'::jsonb)) LOOP IF NOT (k=ANY(allowed)) THEN RAISE EXCEPTION 'invalid audit metadata' USING errcode='22023'; END IF; END LOOP;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS phase5_validate_audit_row ON public.audit_log;
CREATE TRIGGER phase5_validate_audit_row BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION public.phase5_validate_audit_row();

CREATE OR REPLACE FUNCTION public.phase5_domain_invariants() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_TABLE_NAME='client_related_party' AND NEW.status='active' THEN
    IF NOT EXISTS (SELECT 1 FROM public.client c WHERE c.id=NEW.client_id AND c.office_id=NEW.office_id AND c.status='active') THEN RAISE EXCEPTION 'client must be active in same office' USING errcode='23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.party p WHERE p.id=NEW.party_id AND p.office_id=NEW.office_id AND p.status='active') THEN RAISE EXCEPTION 'party must be active in same office' USING errcode='23514'; END IF;
  END IF;
  IF TG_TABLE_NAME='client' AND NEW.status='active' AND NOT EXISTS (SELECT 1 FROM public.party p WHERE p.id=NEW.party_id AND p.office_id=NEW.office_id AND p.status='active') THEN RAISE EXCEPTION 'client party must be active' USING errcode='23514'; END IF;
  IF TG_TABLE_NAME='party' AND OLD.status='active' AND NEW.status='inactive' THEN
    IF EXISTS (SELECT 1 FROM public.client c WHERE c.party_id=OLD.id AND c.office_id=OLD.office_id AND c.status='active') THEN RAISE EXCEPTION 'cannot deactivate party with active client' USING errcode='23514'; END IF;
    IF EXISTS (SELECT 1 FROM public.client_related_party r WHERE r.party_id=OLD.id AND r.office_id=OLD.office_id AND r.status='active') THEN RAISE EXCEPTION 'cannot deactivate party with active relation' USING errcode='23514'; END IF;
  END IF;
  IF TG_TABLE_NAME='client' AND OLD.status='active' AND NEW.status='inactive' AND EXISTS (SELECT 1 FROM public.client_related_party r WHERE r.client_id=OLD.id AND r.office_id=OLD.office_id AND r.status='active') THEN RAISE EXCEPTION 'cannot deactivate client with active relation' USING errcode='23514'; END IF;
  IF TG_TABLE_NAME='client_related_party' AND NEW.confirmation_status <> OLD.confirmation_status THEN
    IF OLD.confirmation_status <> 'pending' OR NEW.confirmation_status NOT IN ('confirmed','rejected') THEN RAISE EXCEPTION 'invalid relation transition' USING errcode='22023'; END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS phase5_domain_invariants_party ON public.party;
DROP TRIGGER IF EXISTS phase5_domain_invariants_client ON public.client;
DROP TRIGGER IF EXISTS phase5_domain_invariants_relation ON public.client_related_party;
CREATE TRIGGER phase5_domain_invariants_party BEFORE UPDATE ON public.party FOR EACH ROW EXECUTE FUNCTION public.phase5_domain_invariants();
CREATE TRIGGER phase5_domain_invariants_client BEFORE UPDATE ON public.client FOR EACH ROW EXECUTE FUNCTION public.phase5_domain_invariants();
CREATE TRIGGER phase5_domain_invariants_relation BEFORE INSERT OR UPDATE ON public.client_related_party FOR EACH ROW EXECUTE FUNCTION public.phase5_domain_invariants();

COMMENT ON COLUMN public.client_related_party.relation_type IS 'Allowlist: subsidiary, family_member, dependent, representative, other.';
