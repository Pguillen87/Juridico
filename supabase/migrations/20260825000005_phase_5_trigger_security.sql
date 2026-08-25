SET lock_timeout = '2s';
ALTER FUNCTION public.phase5_domain_invariants() SECURITY DEFINER;
ALTER FUNCTION public.phase5_domain_invariants() SET search_path = pg_catalog, public;
