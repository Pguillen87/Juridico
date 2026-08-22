BEGIN;

SELECT plan(19);

CREATE OR REPLACE FUNCTION set_auth_user(user_id UUID) RETURNS void AS $$
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', user_id), true);
END;
$$ LANGUAGE plpgsql;

SELECT set_config('role', 'postgres', true);
INSERT INTO auth.users (id, email) VALUES
    ('30000000-0000-0000-0000-000000000001', 'rate-owner-a@test.local'),
    ('30000000-0000-0000-0000-000000000002', 'rate-owner-b@test.local'),
    ('30000000-0000-0000-0000-000000000003', 'rate-inactive@test.local'),
    ('30000000-0000-0000-0000-000000000004', 'rate-auditor@test.local');
INSERT INTO public.office (id, name, is_active) VALUES
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Rate Office A', true),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Rate Office B', true);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES
    ('30000000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Rate Owner A', 'lawyer', true, true),
    ('30000000-0000-0000-0000-000000000002', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'Rate Owner B', 'operator', true, true),
    ('30000000-0000-0000-0000-000000000003', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Rate Inactive', 'lawyer', false, false),
    ('30000000-0000-0000-0000-000000000004', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Rate Auditor', 'auditor', false, true);

SELECT is(
    (SELECT rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'rate_limit_bucket'),
    true,
    'A. rate limit bucket has RLS enabled'
);
SELECT set_auth_user('30000000-0000-0000-0000-000000000001');
SELECT throws_ok(
    $$ SELECT count(*) FROM public.rate_limit_bucket $$,
    '42501',
    NULL,
    'B. authenticated cannot inspect rate limit buckets directly'
);

SELECT (public.consume_admin_rate_limit('admin.invite')).* \gset first_
SELECT is(:'first_allowed'::text, 't'::text, 'C. first invite request is allowed');
SELECT is(:'first_current_count'::text, '1'::text, 'D. first invite request starts count at one');
SELECT is(:'first_limit_count'::text, '5'::text, 'E. invite default is five per window');
SELECT is(:'first_window_seconds'::text, '900'::text, 'F. invite window default is fifteen minutes');

SELECT (public.consume_admin_rate_limit('admin.invite')).*;
SELECT (public.consume_admin_rate_limit('admin.invite')).*;
SELECT (public.consume_admin_rate_limit('admin.invite')).*;
SELECT (public.consume_admin_rate_limit('admin.invite')).* \gset fifth_
SELECT is(:'fifth_allowed'::text, 't'::text, 'G. fifth invite request is allowed');
SELECT is(:'fifth_current_count'::text, '5'::text, 'H. fifth invite request reaches the configured limit');
SELECT (public.consume_admin_rate_limit('admin.invite')).* \gset sixth_
SELECT is(:'sixth_allowed'::text, 'f'::text, 'I. sixth invite request is blocked');
SELECT ok((:'sixth_retry_after_seconds')::integer > 0, 'J. blocked request returns a positive retry-after');

SELECT (public.consume_admin_rate_limit('admin.change_role')).* \gset role_bucket_
SELECT is(:'role_bucket_current_count'::text, '1'::text, 'K. operation key has an independent bucket');
SELECT is(:'role_bucket_limit_count'::text, '20'::text, 'L. change_role default is twenty per window');

SELECT set_auth_user('30000000-0000-0000-0000-000000000002');
SELECT (public.consume_admin_rate_limit('admin.invite')).* \gset office_bucket_
SELECT is(:'office_bucket_current_count'::text, '1'::text, 'M. another office does not share the first bucket');

SELECT set_auth_user('30000000-0000-0000-0000-000000000004');
SELECT (public.consume_admin_rate_limit('admin.audit_export')).* \gset audit_bucket_
SELECT is(:'audit_bucket_allowed'::text, 't'::text, 'N. auditor can consume the export bucket');
SELECT is(:'audit_bucket_limit_count'::text, '3'::text, 'O. audit export default is three per hour');

SELECT set_config('role', 'postgres', true);
UPDATE public.rate_limit_bucket
   SET window_started_at = now() - interval '16 minutes'
 WHERE office_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
   AND actor_user_id = '30000000-0000-0000-0000-000000000001'
   AND operation = 'admin.invite';
SELECT set_auth_user('30000000-0000-0000-0000-000000000001');
SELECT (public.consume_admin_rate_limit('admin.invite')).* \gset reset_
SELECT is(:'reset_allowed'::text, 't'::text,     'P. expired window resets and allows request');
SELECT is(:'reset_current_count'::text, '1'::text,     'Q. expired window restarts count at one');

SELECT set_config('role', 'postgres', true);
SELECT is(
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'rate_limit_bucket'
        AND column_name IN ('email', 'ip')),
    0::bigint,
    'R. rate limit bucket does not store raw email or IP'
);
UPDATE public.user_profile SET is_active = false
 WHERE id = '30000000-0000-0000-0000-000000000003';
SELECT set_auth_user('30000000-0000-0000-0000-000000000003');
SELECT throws_ok(
    $$ SELECT public.consume_admin_rate_limit('admin.invite') $$,
    '42501',
    NULL,
    'S. inactive actor cannot consume a rate limit bucket'
);

SELECT * FROM finish();
ROLLBACK;
