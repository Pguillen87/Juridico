SET lock_timeout = '2s';

REVOKE ALL ON FUNCTION public.phase13_create_client_contact(UUID,TEXT,TEXT), public.phase13_confirm_client_contact(UUID), public.phase13_deactivate_client_contact(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.phase13_create_client_contact(UUID,TEXT,TEXT), public.phase13_confirm_client_contact(UUID), public.phase13_deactivate_client_contact(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.phase13_reconcile_unknown_delivery(UUID,BOOLEAN,TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.phase13_reconcile_unknown_delivery_with_evidence(
  p_delivery_id UUID, p_evidence TEXT, p_reason TEXT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE d public.email_delivery%ROWTYPE; a public.user_profile; n INTEGER; next_status TEXT;
BEGIN
  IF current_user <> 'service_role' OR p_evidence NOT IN ('positive_confirmation','negative_confirmation','still_unknown')
     OR p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid reconciliation evidence' USING ERRCODE='22023';
  END IF;
  SELECT * INTO d FROM public.email_delivery WHERE id=p_delivery_id FOR UPDATE;
  IF d.id IS NULL OR d.status <> 'unknown_outcome' THEN RAISE EXCEPTION 'delivery is not awaiting reconciliation' USING ERRCODE='P0001'; END IF;
  SELECT count(*) INTO n FROM public.email_delivery_attempt WHERE office_id=d.office_id AND delivery_id=d.id;
  next_status := CASE WHEN p_evidence='positive_confirmation' THEN 'delivered' WHEN p_evidence='negative_confirmation' AND n < 3 THEN 'retry_available' WHEN p_evidence='negative_confirmation' THEN 'failed' ELSE 'unknown_outcome' END;
  IF next_status = 'unknown_outcome' THEN RETURN next_status; END IF;
  PERFORM set_config('juridico.phase13_internal','1',true);
  UPDATE public.email_delivery SET status=next_status, sent_at=CASE WHEN next_status='delivered' THEN clock_timestamp() ELSE NULL END, reconciled_at=clock_timestamp() WHERE id=d.id;
  SELECT up.* INTO a FROM public.user_profile up WHERE up.id=d.created_by;
  PERFORM public.phase13_write_audit('email_delivery.reconciled','email_delivery',d.id,d.office_id,a.id,jsonb_build_object('before_status','unknown_outcome','after_status',next_status,'reason',btrim(p_reason),'result',p_evidence,'correlation_id',gen_random_uuid()));
  RETURN next_status;
END; $$;
REVOKE ALL ON FUNCTION public.phase13_reconcile_unknown_delivery_with_evidence(UUID,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phase13_reconcile_unknown_delivery_with_evidence(UUID,TEXT,TEXT) TO service_role;
