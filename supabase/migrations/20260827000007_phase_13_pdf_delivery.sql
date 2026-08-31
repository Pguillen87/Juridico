SET lock_timeout = '2s';

-- Fase 13: storage privado somente local/sandbox; nenhum provider externo é configurado.
INSERT INTO storage.buckets (id, name, public)
VALUES ('private-reports', 'private-reports', false)
ON CONFLICT (id) DO UPDATE SET public = false;

CREATE TABLE public.client_contact (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  client_id UUID NOT NULL,
  display_name TEXT NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 240),
  email TEXT NOT NULL CHECK (email = lower(btrim(email)) AND email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' AND char_length(email) <= 320),
  is_confirmed BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  confirmed_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((is_confirmed = true) = (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)),
  UNIQUE (office_id, id),
  UNIQUE (office_id, client_id, email),
  FOREIGN KEY (office_id, client_id) REFERENCES public.client(office_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.report_artifact (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  report_id UUID NOT NULL,
  report_version_id UUID NOT NULL,
  artifact_type TEXT NOT NULL DEFAULT 'pdf' CHECK (artifact_type = 'pdf'),
  storage_bucket TEXT NOT NULL DEFAULT 'private-reports' CHECK (storage_bucket = 'private-reports'),
  private_storage_uri TEXT NOT NULL CHECK (private_storage_uri ~ '^private://private-reports/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}\.pdf$'),
  approved_hash TEXT NOT NULL CHECK (approved_hash ~ '^[0-9a-f]{64}$'),
  file_hash TEXT NOT NULL CHECK (file_hash ~ '^[0-9a-f]{64}$'),
  generation_fingerprint TEXT NOT NULL CHECK (generation_fingerprint ~ '^[0-9a-f]{64}$'),
  byte_size BIGINT NOT NULL CHECK (byte_size > 0),
  created_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  FOREIGN KEY (office_id, report_id) REFERENCES public.weekly_report(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, report_version_id) REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT
);
CREATE INDEX report_artifact_report_idx ON public.report_artifact (office_id, report_id, created_at DESC);
CREATE INDEX report_artifact_version_idx ON public.report_artifact (office_id, report_version_id, created_at DESC);
CREATE INDEX report_artifact_hash_idx ON public.report_artifact (office_id, file_hash);
CREATE UNIQUE INDEX report_artifact_generation_idx ON public.report_artifact (office_id, generation_fingerprint);

CREATE TABLE public.email_delivery (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  report_id UUID NOT NULL,
  report_version_id UUID NOT NULL,
  artifact_id UUID NOT NULL,
  client_contact_id UUID NOT NULL,
  recipient TEXT NOT NULL CHECK (recipient = lower(btrim(recipient)) AND recipient ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' AND char_length(recipient) <= 320),
  subject TEXT NOT NULL CHECK (char_length(btrim(subject)) BETWEEN 1 AND 240),
  approved_hash TEXT NOT NULL CHECK (approved_hash ~ '^[0-9a-f]{64}$'),
  artifact_hash TEXT NOT NULL CHECK (artifact_hash ~ '^[0-9a-f]{64}$'),
  private_pdf_uri TEXT NOT NULL CHECK (private_pdf_uri ~ '^private://private-reports/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}\.pdf$'),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','delivered','retry_available','failed','unknown_outcome')),
  idempotency_key TEXT NOT NULL CHECK (char_length(btrim(idempotency_key)) BETWEEN 1 AND 240),
  reason TEXT CHECK (reason IS NULL OR (char_length(btrim(reason)) BETWEEN 1 AND 500)),
  created_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  reconciled_at TIMESTAMPTZ,
  reconciled_by UUID REFERENCES auth.users(id) ON DELETE RESTRICT,
  UNIQUE (office_id, id),
  UNIQUE (office_id, idempotency_key),
  FOREIGN KEY (office_id, report_id) REFERENCES public.weekly_report(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, report_version_id) REFERENCES public.report_version(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, artifact_id) REFERENCES public.report_artifact(office_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (office_id, client_contact_id) REFERENCES public.client_contact(office_id, id) ON DELETE RESTRICT,
  CHECK ((status = 'delivered') = (sent_at IS NOT NULL)),
  CHECK (status <> 'unknown_outcome' OR (reconciled_at IS NULL AND reconciled_by IS NULL)),
  CHECK ((reconciled_at IS NULL) = (reconciled_by IS NULL))
);
CREATE INDEX email_delivery_report_idx ON public.email_delivery (office_id, report_id, created_at DESC);
CREATE INDEX email_delivery_version_status_idx ON public.email_delivery (office_id, report_version_id, status, created_at DESC);
CREATE INDEX email_delivery_recipient_idx ON public.email_delivery (office_id, recipient, created_at DESC);

CREATE TABLE public.email_delivery_attempt (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  delivery_id UUID NOT NULL,
  attempt_number INTEGER NOT NULL CHECK (attempt_number BETWEEN 1 AND 3),
  outcome TEXT NOT NULL CHECK (outcome IN ('processing','delivered','retry_available','failed','unknown_outcome')),
  provider_response_sanitized JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(provider_response_sanitized) = 'object'),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, id),
  UNIQUE (office_id, delivery_id, attempt_number),
  FOREIGN KEY (office_id, delivery_id) REFERENCES public.email_delivery(office_id, id) ON DELETE RESTRICT,
  CHECK (completed_at IS NULL OR completed_at >= started_at)
);
CREATE INDEX email_delivery_attempt_delivery_idx ON public.email_delivery_attempt (office_id, delivery_id, attempt_number DESC);

CREATE TABLE public.email_delivery_retry_command (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL,
  delivery_id UUID NOT NULL,
  idempotency_key TEXT NOT NULL CHECK (char_length(btrim(idempotency_key)) BETWEEN 1 AND 240),
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (office_id, delivery_id, idempotency_key),
  FOREIGN KEY (office_id, delivery_id) REFERENCES public.email_delivery(office_id, id) ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION public.phase13_block_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF current_setting('juridico.phase13_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION '% is append-only and internal-only', TG_TABLE_NAME USING ERRCODE = '42501';
  END IF;
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION '% is append-only and has no physical mutation', TG_TABLE_NAME USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_block_attempt_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF current_setting('juridico.phase13_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION '% is writable only by phase 13 domain functions', TG_TABLE_NAME USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '% has no physical deletion', TG_TABLE_NAME USING ERRCODE = '42501';
  END IF;
  IF OLD.id IS DISTINCT FROM NEW.id OR OLD.office_id IS DISTINCT FROM NEW.office_id
     OR OLD.delivery_id IS DISTINCT FROM NEW.delivery_id OR OLD.attempt_number IS DISTINCT FROM NEW.attempt_number
     OR OLD.started_at IS DISTINCT FROM NEW.started_at OR OLD.created_at IS DISTINCT FROM NEW.created_at
  THEN RAISE EXCEPTION 'email_delivery_attempt identity is immutable' USING ERRCODE='42501'; END IF;
  IF OLD.outcome <> 'processing' OR NEW.outcome = 'processing'
     OR NEW.completed_at IS NULL OR NEW.completed_at < OLD.started_at
  THEN RAISE EXCEPTION 'email_delivery_attempt transition is invalid' USING ERRCODE='42501'; END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_block_delivery_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF current_setting('juridico.phase13_internal', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION '% is writable only by phase 13 domain functions', TG_TABLE_NAME USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION '% has no physical deletion', TG_TABLE_NAME USING ERRCODE = '42501'; END IF;
  IF OLD.id IS DISTINCT FROM NEW.id OR OLD.office_id IS DISTINCT FROM NEW.office_id
     OR OLD.report_id IS DISTINCT FROM NEW.report_id OR OLD.report_version_id IS DISTINCT FROM NEW.report_version_id
     OR OLD.artifact_id IS DISTINCT FROM NEW.artifact_id OR OLD.client_contact_id IS DISTINCT FROM NEW.client_contact_id
     OR OLD.recipient IS DISTINCT FROM NEW.recipient OR OLD.subject IS DISTINCT FROM NEW.subject
     OR OLD.approved_hash IS DISTINCT FROM NEW.approved_hash OR OLD.artifact_hash IS DISTINCT FROM NEW.artifact_hash OR OLD.private_pdf_uri IS DISTINCT FROM NEW.private_pdf_uri
     OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key OR OLD.created_by IS DISTINCT FROM NEW.created_by
     OR OLD.created_at IS DISTINCT FROM NEW.created_at OR OLD.reason IS DISTINCT FROM NEW.reason
  THEN RAISE EXCEPTION 'email_delivery identity is immutable' USING ERRCODE = '42501'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER phase13_artifact_append_only BEFORE UPDATE OR DELETE ON public.report_artifact FOR EACH ROW EXECUTE FUNCTION public.phase13_block_append_only();
CREATE TRIGGER phase13_attempt_append_only BEFORE UPDATE OR DELETE ON public.email_delivery_attempt FOR EACH ROW EXECUTE FUNCTION public.phase13_block_attempt_mutation();
CREATE TRIGGER phase13_delivery_guard BEFORE UPDATE OR DELETE ON public.email_delivery FOR EACH ROW EXECUTE FUNCTION public.phase13_block_delivery_mutation();

ALTER TABLE public.client_contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_artifact ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_delivery_attempt ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_delivery_retry_command ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.client_contact, public.report_artifact, public.email_delivery, public.email_delivery_attempt, public.email_delivery_retry_command FROM PUBLIC, anon, authenticated, service_role;
-- F13 tables are never directly readable by browser roles. Server-only domain functions
-- enforce D-022; the auditor receives only sanitized audit_log events.
CREATE POLICY phase13_contact_select ON public.client_contact FOR SELECT TO authenticated USING (false);
CREATE POLICY phase13_artifact_select ON public.report_artifact FOR SELECT TO authenticated USING (false);
CREATE POLICY phase13_delivery_select ON public.email_delivery FOR SELECT TO authenticated USING (false);
CREATE POLICY phase13_attempt_select ON public.email_delivery_attempt FOR SELECT TO authenticated USING (false);

CREATE OR REPLACE FUNCTION public.phase13_assert_actor(p_role TEXT DEFAULT 'lawyer')
RETURNS public.user_profile LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile;
BEGIN
  SELECT up.* INTO a FROM public.user_profile up JOIN public.office o ON o.id=up.office_id
   WHERE up.id=auth.uid() AND up.is_active AND o.is_active;
  IF a.id IS NULL OR a.role::TEXT <> p_role THEN RAISE EXCEPTION 'permission denied' USING ERRCODE='42501'; END IF;
  RETURN a;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_write_audit(p_action TEXT, p_entity_type TEXT, p_entity_id UUID, p_office_id UUID, p_actor UUID, p_metadata JSONB)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x BIGINT; k TEXT;
BEGIN
  IF p_action NOT IN ('report_artifact.created','report_artifact.download_requested','email_delivery.authorized','email_delivery.attempted','email_delivery.reconciled','email_delivery.retry_requested','email_delivery.resent','client_contact.created','client_contact.confirmed','client_contact.deactivated')
     OR p_entity_type NOT IN ('report_artifact','email_delivery','email_delivery_attempt','client_contact')
     OR p_metadata IS NULL OR jsonb_typeof(p_metadata)<>'object' THEN RAISE EXCEPTION 'invalid phase 13 audit event' USING ERRCODE='22023'; END IF;
  FOR k IN SELECT jsonb_object_keys(p_metadata) LOOP
    IF k NOT IN ('report_id','report_version_id','artifact_id','delivery_id','attempt_number','status','before_status','after_status','result','idempotency_key','reason','file_hash','recipient_domain','correlation_id') THEN RAISE EXCEPTION 'phase 13 audit key is not allowlisted' USING ERRCODE='22023'; END IF;
  END LOOP;
  INSERT INTO public.audit_log(audit_scope,office_id,actor_user_id,action,entity_type,entity_id,metadata)
  VALUES ('operational',p_office_id,p_actor,p_action,p_entity_type,p_entity_id,p_metadata) RETURNING id INTO x;
  RETURN x;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_create_client_contact(p_client_id UUID,p_email TEXT,p_display_name TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile; c UUID; normalized TEXT;
BEGIN
  a := public.phase13_assert_actor('lawyer'); normalized := lower(btrim(p_email));
  IF normalized !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR char_length(normalized)>320 OR p_display_name IS NULL OR char_length(btrim(p_display_name)) NOT BETWEEN 1 AND 240 THEN RAISE EXCEPTION 'invalid contact input' USING ERRCODE='22023'; END IF;
  PERFORM 1 FROM public.client WHERE office_id=a.office_id AND id=p_client_id AND status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'client is not active' USING ERRCODE='P0001'; END IF;
  INSERT INTO public.client_contact(office_id,client_id,email,display_name,created_at,updated_at) VALUES(a.office_id,p_client_id,normalized,btrim(p_display_name),clock_timestamp(),clock_timestamp()) RETURNING id INTO c;
  PERFORM public.phase13_write_audit('client_contact.created','client_contact',c,a.office_id,a.id,jsonb_build_object('result','created','correlation_id',gen_random_uuid()));
  RETURN c;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_confirm_client_contact(p_contact_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  UPDATE public.client_contact SET is_confirmed=true,confirmed_by=a.id,confirmed_at=clock_timestamp(),updated_at=clock_timestamp() WHERE office_id=a.office_id AND id=p_contact_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'contact is not active' USING ERRCODE='P0001'; END IF;
  PERFORM public.phase13_write_audit('client_contact.confirmed','client_contact',p_contact_id,a.office_id,a.id,jsonb_build_object('result','confirmed','correlation_id',gen_random_uuid()));
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_deactivate_client_contact(p_contact_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  UPDATE public.client_contact SET is_active=false,updated_at=clock_timestamp() WHERE office_id=a.office_id AND id=p_contact_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'contact not found' USING ERRCODE='P0002'; END IF;
  PERFORM public.phase13_write_audit('client_contact.deactivated','client_contact',p_contact_id,a.office_id,a.id,jsonb_build_object('result','deactivated','correlation_id',gen_random_uuid()));
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_generate_final_pdf(p_report_id UUID, p_report_version_id UUID, p_approved_hash TEXT, p_file_hash TEXT, p_generation_fingerprint TEXT, p_private_storage_uri TEXT, p_byte_size BIGINT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile; r public.weekly_report%ROWTYPE; v public.report_version%ROWTYPE; id UUID;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  IF p_approved_hash !~ '^[0-9a-f]{64}$' OR p_file_hash !~ '^[0-9a-f]{64}$' OR p_generation_fingerprint !~ '^[0-9a-f]{64}$' OR p_private_storage_uri !~ '^private://private-reports/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}\.pdf$' OR p_byte_size <= 0 THEN RAISE EXCEPTION 'invalid artifact input' USING ERRCODE='22023'; END IF;
  SELECT wr.* INTO r FROM public.weekly_report AS wr WHERE wr.office_id=a.office_id AND wr.id=p_report_id;
  SELECT rv.* INTO v FROM public.report_version AS rv WHERE rv.office_id=a.office_id AND rv.id=p_report_version_id AND rv.report_id=p_report_id;
  IF r.id IS NULL OR v.id IS NULL OR r.status <> 'approved' OR r.approved_version_id IS DISTINCT FROM v.id OR r.approved_hash IS DISTINCT FROM v.content_hash OR p_approved_hash IS DISTINCT FROM r.approved_hash THEN RAISE EXCEPTION 'report is not approved for this artifact' USING ERRCODE='P0001'; END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects AS so WHERE so.bucket_id='private-reports' AND so.name=replace(p_private_storage_uri, 'private://private-reports/', '') AND CASE WHEN so.metadata->>'size' ~ '^[0-9]+$' THEN (so.metadata->>'size')::bigint ELSE p_byte_size END=p_byte_size) THEN RAISE EXCEPTION 'artifact object is not present in private storage' USING ERRCODE='P0001'; END IF;
  SELECT ra.id INTO id FROM public.report_artifact AS ra WHERE ra.office_id=a.office_id AND ra.generation_fingerprint=p_generation_fingerprint;
  IF id IS NOT NULL THEN RETURN id; END IF;
  PERFORM set_config('juridico.phase13_internal','1',true);
  INSERT INTO public.report_artifact(office_id,report_id,report_version_id,approved_hash,private_storage_uri,file_hash,generation_fingerprint,byte_size,created_by)
  VALUES(a.office_id,r.id,v.id,p_approved_hash,p_private_storage_uri,p_file_hash,p_generation_fingerprint,p_byte_size,a.id)
  ON CONFLICT (office_id,generation_fingerprint) DO NOTHING RETURNING report_artifact.id INTO id;
  IF id IS NULL THEN
    SELECT ra.id INTO id FROM public.report_artifact AS ra
      WHERE ra.office_id=a.office_id AND ra.generation_fingerprint=p_generation_fingerprint;
    IF id IS NULL THEN RAISE EXCEPTION 'artifact generation replay could not be resolved' USING ERRCODE='P0001'; END IF;
    RETURN id;
  END IF;
  PERFORM public.phase13_write_audit('report_artifact.created','report_artifact',id,a.office_id,a.id,jsonb_build_object('report_id',r.id,'report_version_id',v.id,'file_hash',p_file_hash,'result','created','correlation_id',gen_random_uuid()));
  RETURN id;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_authorize_send(p_report_id UUID,p_report_version_id UUID,p_artifact_id UUID,p_client_contact_id UUID,p_subject TEXT,p_idempotency_key TEXT,p_reason TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile; r public.weekly_report%ROWTYPE; v public.report_version%ROWTYPE; f public.report_artifact%ROWTYPE; c public.client_contact%ROWTYPE; d UUID; created_new BOOLEAN := false;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  IF p_subject IS NULL OR char_length(btrim(p_subject)) NOT BETWEEN 1 AND 240 OR p_idempotency_key IS NULL OR char_length(btrim(p_idempotency_key)) NOT BETWEEN 1 AND 240 THEN RAISE EXCEPTION 'invalid send input' USING ERRCODE='22023'; END IF;
  SELECT wr.* INTO r FROM public.weekly_report AS wr WHERE wr.office_id=a.office_id AND wr.id=p_report_id;
  SELECT rv.* INTO v FROM public.report_version AS rv WHERE rv.office_id=a.office_id AND rv.id=p_report_version_id AND rv.report_id=p_report_id;
  SELECT * INTO f FROM public.report_artifact WHERE office_id=a.office_id AND id=p_artifact_id AND report_id=p_report_id AND report_version_id=p_report_version_id;
  SELECT * INTO c FROM public.client_contact WHERE office_id=a.office_id AND id=p_client_contact_id AND is_active AND is_confirmed;
  IF r.id IS NULL OR v.id IS NULL OR f.id IS NULL OR c.id IS NULL OR r.status <> 'approved' OR r.approved_version_id IS DISTINCT FROM v.id OR r.approved_hash IS DISTINCT FROM v.content_hash THEN RAISE EXCEPTION 'invalid approved delivery inputs' USING ERRCODE='P0001'; END IF;
  PERFORM set_config('juridico.phase13_internal','1',true);
  INSERT INTO public.email_delivery(office_id,report_id,report_version_id,artifact_id,client_contact_id,recipient,subject,approved_hash,artifact_hash,private_pdf_uri,idempotency_key,reason,created_by)
  VALUES(a.office_id,r.id,v.id,f.id,c.id,c.email,btrim(p_subject),f.approved_hash,f.file_hash,f.private_storage_uri,btrim(p_idempotency_key),p_reason,a.id)
  ON CONFLICT (office_id,idempotency_key) DO NOTHING RETURNING email_delivery.id INTO d;
  IF d IS NULL THEN
    SELECT id INTO d FROM public.email_delivery WHERE office_id=a.office_id AND idempotency_key=btrim(p_idempotency_key);
    IF d IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.email_delivery WHERE id=d AND report_id=r.id AND report_version_id=v.id AND artifact_id=f.id AND client_contact_id=c.id AND recipient=c.email AND subject=btrim(p_subject)) THEN
      RAISE EXCEPTION 'idempotency key reused with different delivery request' USING ERRCODE='23505';
    END IF;
  END IF;
  PERFORM public.phase13_write_audit('email_delivery.authorized','email_delivery',d,a.office_id,a.id,jsonb_build_object('report_id',r.id,'report_version_id',v.id,'artifact_id',f.id,'recipient_domain',split_part(c.email,'@',2),'status','pending','idempotency_key',btrim(p_idempotency_key),'result','authorized','correlation_id',gen_random_uuid()));
  RETURN d;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_reconcile_unknown_delivery(p_delivery_id UUID,p_delivered BOOLEAN,p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile; d public.email_delivery%ROWTYPE; new_status TEXT;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  SELECT * INTO d FROM public.email_delivery WHERE office_id=a.office_id AND id=p_delivery_id FOR UPDATE;
  IF d.id IS NULL OR d.status <> 'unknown_outcome' OR p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'delivery is not awaiting reconciliation' USING ERRCODE='P0001'; END IF;
  new_status := CASE WHEN p_delivered THEN 'delivered' ELSE 'failed' END;
  PERFORM set_config('juridico.phase13_internal','1',true);
  UPDATE public.email_delivery SET status=new_status,sent_at=CASE WHEN p_delivered THEN clock_timestamp() ELSE NULL END,reconciled_at=clock_timestamp(),reconciled_by=a.id WHERE office_id=a.office_id AND id=d.id;
  PERFORM public.phase13_write_audit('email_delivery.reconciled','email_delivery',d.id,a.office_id,a.id,jsonb_build_object('before_status','unknown_outcome','after_status',new_status,'reason',btrim(p_reason),'result','reconciled','correlation_id',gen_random_uuid()));
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_claim_delivery_attempt(p_delivery_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE d public.email_delivery%ROWTYPE; attempt_id UUID; n INTEGER;
BEGIN
  IF current_user NOT IN ('postgres','service_role') THEN RAISE EXCEPTION 'permission denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO d FROM public.email_delivery WHERE id=p_delivery_id FOR UPDATE;
  IF d.id IS NULL OR d.status NOT IN ('pending','retry_available') THEN RAISE EXCEPTION 'delivery is not claimable' USING ERRCODE='P0001'; END IF;
  SELECT count(*) + 1 INTO n FROM public.email_delivery_attempt WHERE office_id=d.office_id AND delivery_id=d.id;
  IF n > 3 THEN RAISE EXCEPTION 'delivery attempt limit exceeded' USING ERRCODE='P0001'; END IF;
  PERFORM set_config('juridico.phase13_internal','1',true);
  INSERT INTO public.email_delivery_attempt(office_id,delivery_id,attempt_number,outcome)
    VALUES(d.office_id,d.id,n,'processing') RETURNING id INTO attempt_id;
  UPDATE public.email_delivery SET status='processing',sent_at=NULL WHERE office_id=d.office_id AND id=d.id;
  PERFORM public.phase13_write_audit('email_delivery.attempted','email_delivery_attempt',attempt_id,d.office_id,NULL,jsonb_build_object('delivery_id',d.id,'attempt_number',n,'status','processing','result','claimed','correlation_id',gen_random_uuid()));
  RETURN attempt_id;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_record_delivery_attempt(p_delivery_id UUID,p_attempt_number INTEGER,p_outcome TEXT,p_provider_response_sanitized JSONB DEFAULT '{}'::jsonb)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE d public.email_delivery%ROWTYPE; attempt_id UUID; k TEXT; completed_at_value TIMESTAMPTZ;
BEGIN
  IF current_user NOT IN ('postgres','service_role') OR p_attempt_number NOT BETWEEN 1 AND 3
     OR p_outcome NOT IN ('delivered','retry_available','failed','unknown_outcome')
     OR p_provider_response_sanitized IS NULL OR jsonb_typeof(p_provider_response_sanitized)<>'object'
  THEN RAISE EXCEPTION 'invalid delivery attempt input' USING ERRCODE='22023'; END IF;
  FOR k IN SELECT jsonb_object_keys(p_provider_response_sanitized) LOOP
    IF k NOT IN ('provider_code','provider_message_code','provider_id','accepted','transient','http_status') THEN RAISE EXCEPTION 'provider response key is not allowlisted' USING ERRCODE='22023'; END IF;
  END LOOP;
  SELECT * INTO d FROM public.email_delivery WHERE id=p_delivery_id FOR UPDATE;
  SELECT id INTO attempt_id FROM public.email_delivery_attempt WHERE office_id=d.office_id AND delivery_id=d.id AND attempt_number=p_attempt_number AND outcome='processing' FOR UPDATE;
  IF d.id IS NULL OR d.status <> 'processing' OR attempt_id IS NULL THEN RAISE EXCEPTION 'delivery has no processing attempt' USING ERRCODE='P0001'; END IF;
  completed_at_value := clock_timestamp();
  PERFORM set_config('juridico.phase13_internal','1',true);
  UPDATE public.email_delivery_attempt SET outcome=p_outcome,provider_response_sanitized=p_provider_response_sanitized,completed_at=completed_at_value WHERE id=attempt_id;
  UPDATE public.email_delivery SET status=p_outcome,sent_at=CASE WHEN p_outcome='delivered' THEN completed_at_value ELSE NULL END WHERE office_id=d.office_id AND id=d.id AND status='processing';
  PERFORM public.phase13_write_audit('email_delivery.attempted','email_delivery_attempt',attempt_id,d.office_id,NULL,jsonb_build_object('delivery_id',d.id,'attempt_number',p_attempt_number,'status',p_outcome,'result','recorded','correlation_id',gen_random_uuid()));
  RETURN attempt_id;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_retry_delivery(p_delivery_id UUID,p_idempotency_key TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile; d public.email_delivery%ROWTYPE; n INTEGER; claimed UUID;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  IF p_idempotency_key IS NULL OR char_length(btrim(p_idempotency_key)) NOT BETWEEN 1 AND 240 THEN RAISE EXCEPTION 'invalid retry idempotency key' USING ERRCODE='22023'; END IF;
  SELECT * INTO d FROM public.email_delivery WHERE office_id=a.office_id AND id=p_delivery_id FOR UPDATE;
  IF d.id IS NULL OR d.status <> 'retry_available' THEN RAISE EXCEPTION 'delivery is not retryable' USING ERRCODE='P0001'; END IF;
  SELECT count(*) INTO n FROM public.email_delivery_attempt WHERE office_id=a.office_id AND delivery_id=d.id;
  IF n >= 3 THEN RAISE EXCEPTION 'delivery retry limit exceeded' USING ERRCODE='P0001'; END IF;
  INSERT INTO public.email_delivery_retry_command(office_id,delivery_id,idempotency_key,created_by)
  VALUES (a.office_id,d.id,btrim(p_idempotency_key),a.id)
  ON CONFLICT (office_id,delivery_id,idempotency_key) DO NOTHING
  RETURNING id INTO claimed;
  IF claimed IS NULL THEN RETURN; END IF;
  PERFORM set_config('juridico.phase13_internal','1',true);
  UPDATE public.email_delivery SET status='pending' WHERE office_id=a.office_id AND id=d.id;
  PERFORM public.phase13_write_audit('email_delivery.retry_requested','email_delivery',d.id,a.office_id,a.id,jsonb_build_object('delivery_id',d.id,'status','pending','reason','manual_retry','idempotency_key',btrim(p_idempotency_key),'result','retry_authorized','correlation_id',gen_random_uuid()));
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_resend_delivery(p_delivery_id UUID,p_idempotency_key TEXT,p_reason TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile; old_d public.email_delivery%ROWTYPE; new_id UUID;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  IF p_idempotency_key IS NULL OR char_length(btrim(p_idempotency_key)) NOT BETWEEN 1 AND 240 OR p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'invalid resend input' USING ERRCODE='22023'; END IF;
  SELECT * INTO old_d FROM public.email_delivery WHERE office_id=a.office_id AND id=p_delivery_id AND status IN ('delivered','failed','retry_available') FOR UPDATE;
  IF old_d.id IS NULL THEN RAISE EXCEPTION 'delivery is not resendable' USING ERRCODE='P0001'; END IF;
  PERFORM set_config('juridico.phase13_internal','1',true);
  INSERT INTO public.email_delivery(office_id,report_id,report_version_id,artifact_id,client_contact_id,recipient,subject,approved_hash,artifact_hash,private_pdf_uri,idempotency_key,reason,created_by)
  VALUES(a.office_id,old_d.report_id,old_d.report_version_id,old_d.artifact_id,old_d.client_contact_id,old_d.recipient,old_d.subject,old_d.approved_hash,old_d.artifact_hash,old_d.private_pdf_uri,btrim(p_idempotency_key),btrim(p_reason),a.id)
  ON CONFLICT (office_id,idempotency_key) DO NOTHING
  RETURNING id INTO new_id;
  IF new_id IS NULL THEN
    SELECT id INTO new_id FROM public.email_delivery WHERE office_id=a.office_id AND idempotency_key=btrim(p_idempotency_key);
    IF NOT EXISTS (SELECT 1 FROM public.email_delivery WHERE id=new_id AND office_id=old_d.office_id AND report_id=old_d.report_id AND report_version_id=old_d.report_version_id AND artifact_id=old_d.artifact_id AND client_contact_id=old_d.client_contact_id AND recipient=old_d.recipient AND subject=old_d.subject AND approved_hash=old_d.approved_hash AND artifact_hash=old_d.artifact_hash AND private_pdf_uri=old_d.private_pdf_uri AND reason IS NOT DISTINCT FROM btrim(p_reason)) THEN
      RAISE EXCEPTION 'idempotency key reused with different resend request' USING ERRCODE='23505';
    END IF;
    RETURN new_id;
  END IF;
  PERFORM public.phase13_write_audit('email_delivery.resent','email_delivery',new_id,a.office_id,a.id,jsonb_build_object('report_id',old_d.report_id,'report_version_id',old_d.report_version_id,'artifact_id',old_d.artifact_id,'status','pending','reason','intentional_resend','idempotency_key',btrim(p_idempotency_key),'result','created','correlation_id',gen_random_uuid()));
  RETURN new_id;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_get_delivery_for_send(p_delivery_id UUID)
RETURNS TABLE (delivery_id UUID, attempt_number INTEGER, recipient TEXT, subject TEXT, artifact_hash TEXT, storage_bucket TEXT, storage_object_key TEXT, status TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile; d public.email_delivery%ROWTYPE; n INTEGER;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  SELECT ed.* INTO d FROM public.email_delivery AS ed WHERE ed.office_id=a.office_id AND ed.id=p_delivery_id;
  IF d.id IS NULL OR d.status NOT IN ('pending','retry_available','processing') THEN RAISE EXCEPTION 'delivery is not executable' USING ERRCODE='P0001'; END IF;
  IF d.status = 'processing' THEN SELECT coalesce(max(ea.attempt_number), 0) INTO n FROM public.email_delivery_attempt AS ea WHERE ea.office_id=a.office_id AND ea.delivery_id=d.id AND ea.outcome='processing'; ELSE SELECT count(*) + 1 INTO n FROM public.email_delivery_attempt AS ea WHERE ea.office_id=a.office_id AND ea.delivery_id=d.id; END IF;
  RETURN QUERY SELECT d.id, n, d.recipient, d.subject, d.artifact_hash, 'private-reports'::text, replace(d.private_pdf_uri, 'private://private-reports/', ''), d.status;
END; $$;

CREATE OR REPLACE FUNCTION public.phase13_get_artifact(p_artifact_id UUID)
RETURNS TABLE (artifact_id UUID, report_id UUID, storage_bucket TEXT, storage_object_key TEXT, file_hash TEXT, byte_size BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE a public.user_profile;
BEGIN
  a := public.phase13_assert_actor('lawyer');
  PERFORM public.phase13_write_audit('report_artifact.download_requested','report_artifact',p_artifact_id,a.office_id,a.id,jsonb_build_object('artifact_id',p_artifact_id,'result','authorized','correlation_id',gen_random_uuid()));
  RETURN QUERY SELECT ra.id, ra.report_id, ra.storage_bucket, replace(ra.private_storage_uri, 'private://private-reports/', ''), ra.file_hash, ra.byte_size
    FROM public.report_artifact AS ra WHERE ra.office_id=a.office_id AND ra.id=p_artifact_id;
END; $$;

REVOKE ALL ON FUNCTION public.phase13_assert_actor(TEXT), public.phase13_write_audit(TEXT,TEXT,UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.phase13_claim_delivery_attempt(UUID), public.phase13_record_delivery_attempt(UUID,INTEGER,TEXT,JSONB) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.phase13_claim_delivery_attempt(UUID), public.phase13_record_delivery_attempt(UUID,INTEGER,TEXT,JSONB) TO service_role;

REVOKE ALL ON FUNCTION public.phase13_generate_final_pdf(UUID,UUID,TEXT,TEXT,TEXT,TEXT,BIGINT), public.phase13_authorize_send(UUID,UUID,UUID,UUID,TEXT,TEXT,TEXT), public.phase13_reconcile_unknown_delivery(UUID,BOOLEAN,TEXT), public.phase13_retry_delivery(UUID,TEXT), public.phase13_resend_delivery(UUID,TEXT,TEXT), public.phase13_get_artifact(UUID), public.phase13_get_delivery_for_send(UUID) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.phase13_generate_final_pdf(UUID,UUID,TEXT,TEXT,TEXT,TEXT,BIGINT), public.phase13_authorize_send(UUID,UUID,UUID,UUID,TEXT,TEXT,TEXT), public.phase13_reconcile_unknown_delivery(UUID,BOOLEAN,TEXT), public.phase13_retry_delivery(UUID,TEXT), public.phase13_resend_delivery(UUID,TEXT,TEXT), public.phase13_get_artifact(UUID), public.phase13_get_delivery_for_send(UUID) TO authenticated;
