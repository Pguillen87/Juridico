SET lock_timeout = '2s';

CREATE OR REPLACE FUNCTION public.phase5_domain_invariants()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'client_related_party' THEN
    IF TG_OP = 'INSERT' AND NEW.status = 'active' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.client c
        WHERE c.id = NEW.client_id
          AND c.office_id = NEW.office_id
          AND c.status = 'active'
      ) THEN
        RAISE EXCEPTION 'client must be active in same office' USING errcode = '23514';
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM public.party p
        WHERE p.id = NEW.party_id
          AND p.office_id = NEW.office_id
          AND p.status = 'active'
      ) THEN
        RAISE EXCEPTION 'party must be active in same office' USING errcode = '23514';
      END IF;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.confirmation_status <> OLD.confirmation_status THEN
      IF OLD.confirmation_status <> 'pending'
         OR NEW.confirmation_status NOT IN ('confirmed', 'rejected') THEN
        RAISE EXCEPTION 'invalid relation transition' USING errcode = '22023';
      END IF;
    END IF;
  ELSIF TG_TABLE_NAME = 'client' THEN
    IF NEW.status = 'active' AND NOT EXISTS (
      SELECT 1 FROM public.party p
      WHERE p.id = NEW.party_id
        AND p.office_id = NEW.office_id
        AND p.status = 'active'
    ) THEN
      RAISE EXCEPTION 'client party must be active' USING errcode = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status = 'inactive'
       AND EXISTS (
         SELECT 1 FROM public.client_related_party r
         WHERE r.client_id = OLD.id
           AND r.office_id = OLD.office_id
           AND r.status = 'active'
       ) THEN
      RAISE EXCEPTION 'cannot deactivate client with active relation' USING errcode = '23514';
    END IF;
  ELSIF TG_TABLE_NAME = 'party' AND TG_OP = 'UPDATE'
        AND OLD.status = 'active' AND NEW.status = 'inactive' THEN
    IF EXISTS (
      SELECT 1 FROM public.client c
      WHERE c.party_id = OLD.id
        AND c.office_id = OLD.office_id
        AND c.status = 'active'
    ) THEN
      RAISE EXCEPTION 'cannot deactivate party with active client' USING errcode = '23514';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.client_related_party r
      WHERE r.party_id = OLD.id
        AND r.office_id = OLD.office_id
        AND r.status = 'active'
    ) THEN
      RAISE EXCEPTION 'cannot deactivate party with active relation' USING errcode = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
