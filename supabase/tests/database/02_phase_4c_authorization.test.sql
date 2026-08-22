BEGIN;

SELECT plan(31);

-- O role authenticated + request.jwt.claims reproduz uma chamada direta com
-- chave publishable e JWT autenticado; a observação pós-operação usa postgres.
CREATE OR REPLACE FUNCTION set_auth_user(user_id UUID) RETURNS void AS $$
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s", "role": "authenticated"}', user_id), true);
END;
$$ LANGUAGE plpgsql;

SELECT set_config('role', 'postgres', true);

INSERT INTO auth.users (id, email) VALUES
    ('10000000-0000-0000-0000-000000000001', 'owner-lawyer-a@test.local'),
    ('10000000-0000-0000-0000-000000000002', 'lawyer-a@test.local'),
    ('10000000-0000-0000-0000-000000000003', 'owner-operator-a@test.local'),
    ('10000000-0000-0000-0000-000000000004', 'operator-a@test.local'),
    ('10000000-0000-0000-0000-000000000005', 'owner-reviewer-a@test.local'),
    ('10000000-0000-0000-0000-000000000006', 'reviewer-a@test.local'),
    ('10000000-0000-0000-0000-000000000007', 'owner-auditor-a@test.local'),
    ('10000000-0000-0000-0000-000000000008', 'auditor-a@test.local'),
    ('10000000-0000-0000-0000-000000000009', 'owner-lawyer-b@test.local'),
    ('10000000-0000-0000-0000-000000000010', 'lawyer-b@test.local');

INSERT INTO public.office (id, name, is_active) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Office 4C A', true),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Office 4C B', true);

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES
    ('10000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Owner Lawyer A', 'lawyer', true, true),
    ('10000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Lawyer A', 'lawyer', false, true),
    ('10000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Owner Operator A', 'operator', true, true),
    ('10000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Operator A', 'operator', false, true),
    ('10000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Owner Reviewer A', 'reviewer', true, true),
    ('10000000-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Reviewer A', 'reviewer', false, true),
    ('10000000-0000-0000-0000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Owner Auditor A', 'auditor', true, true),
    ('10000000-0000-0000-0000-000000000008', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Auditor A', 'auditor', false, true),
    ('10000000-0000-0000-0000-000000000009', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Owner Lawyer B', 'lawyer', true, true),
    ('10000000-0000-0000-0000-000000000010', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Lawyer B', 'lawyer', false, true);

SELECT is(
    (SELECT rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'audit_log'),
    true,
    'A. audit_log has RLS enabled'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000001');
SELECT throws_ok(
    $$ INSERT INTO public.audit_log (audit_scope, office_id, action, entity_type) VALUES ('administrative', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'change_role', 'user_profile') $$,
    '42501',
    NULL,
    'B. authenticated cannot insert audit rows directly'
);
SELECT throws_ok(
    $$ UPDATE public.audit_log SET action = 'tampered' $$,
    '42501',
    NULL,
    'C. authenticated cannot update audit rows'
);
SELECT throws_ok(
    $$ DELETE FROM public.audit_log $$,
    '42501',
    NULL,
    'D. authenticated cannot delete audit rows'
);

SELECT is(
    (SELECT role::text FROM public.change_user_role(
        '10000000-0000-0000-0000-000000000002', 'reviewer'
    )),
    'reviewer',
    'E. active owner can change a same-office role through RPC'
);
SELECT is(
    (SELECT metadata FROM public.get_administrative_audit(100, 'change_role', 'user_profile') LIMIT 1),
    '{"after": {"role": "reviewer"}, "before": {"role": "lawyer"}}'::jsonb,
    'F. change_role audit contains only allowlisted before/after role'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000002');
SELECT throws_ok(
    $$ SELECT public.change_user_role('10000000-0000-0000-0000-000000000004', 'lawyer') $$,
    '42501',
    NULL,
    'G. non-owner cannot change role through direct RPC'
);
SELECT set_auth_user('10000000-0000-0000-0000-000000000001');
SELECT throws_ok(
    $$ SELECT public.change_user_role('10000000-0000-0000-0000-000000000010', 'reviewer') $$,
    'P0002',
    NULL,
    'H. owner cannot target another office through direct RPC'
);
SELECT throws_ok(
    $$ SELECT public.change_user_role('10000000-0000-0000-0000-000000000001', 'operator') $$,
    '42501',
    NULL,
    'I. owner cannot change own role through direct RPC'
);
SELECT throws_ok(
    $$ SELECT public.change_user_role('20000000-0000-0000-0000-000000000099', 'operator') $$,
    'P0002',
    NULL,
    'J. nonexistent target is rejected'
);

SELECT is(
    (SELECT is_active FROM public.set_user_active(
        '10000000-0000-0000-0000-000000000004', false
    )),
    false,
    'K. owner can inactivate a same-office target through RPC'
);
SELECT is(
    (SELECT metadata FROM public.get_administrative_audit(100, 'set_active', 'user_profile') LIMIT 1),
    '{"after": {"is_active": false}, "before": {"is_active": true}}'::jsonb,
    'L. set_active audit contains only allowlisted before/after state'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000004');
SELECT throws_ok(
    $$ SELECT public.change_user_role('10000000-0000-0000-0000-000000000002', 'operator') $$,
    '42501',
    NULL,
    'M. inactive actor cannot call administrative RPC'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000001');
SELECT is(
    (SELECT is_owner FROM public.set_user_owner(
        '10000000-0000-0000-0000-000000000004', true
    )),
    true,
    'N. owner can grant owner to same-office target through RPC'
);
SELECT throws_ok(
    $$ SELECT public.set_user_owner('10000000-0000-0000-0000-000000000001', false) $$,
    '42501',
    NULL,
    'O. owner cannot change own owner status through RPC'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000009');
SELECT throws_ok(
    $$ SELECT public.set_user_active('10000000-0000-0000-0000-000000000009', false) $$,
    'P0001',
    'Cannot remove or deactivate the last active owner of an office',
    'P. last active owner remains protected by database trigger'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000001');
SELECT is(
    (SELECT name FROM public.update_office_name('Office 4C A Renamed')),
    'Office 4C A Renamed',
    'Q. owner can rename only the own active office through RPC'
);
SELECT is(
    (SELECT metadata FROM public.get_administrative_audit(100, 'office.rename', 'office') LIMIT 1),
    '{"after": {"name": "Office 4C A Renamed"}, "before": {"name": "Office 4C A"}}'::jsonb,
    'R. office rename audit contains only allowlisted before/after name'
);
SELECT set_auth_user('10000000-0000-0000-0000-000000000002');
SELECT throws_ok(
    $$ SELECT public.update_office_name('Should Fail') $$,
    '42501',
    NULL,
    'S. non-owner cannot rename office through direct RPC'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000008');
SELECT ok(
    (SELECT count(*) > 0 FROM public.get_administrative_audit(100, NULL, NULL)),
    'T. auditor without owner can read administrative audit in own office'
);
SELECT set_auth_user('10000000-0000-0000-0000-000000000007');
SELECT ok(
    (SELECT count(*) > 0 FROM public.get_administrative_audit(100, NULL, NULL)),
    'U. owner with any functional role can read administrative audit'
);
SELECT set_auth_user('10000000-0000-0000-0000-000000000002');
SELECT throws_ok(
    $$ SELECT * FROM public.get_administrative_audit(100, NULL, NULL) $$,
    '42501',
    NULL,
    'V. non-owner lawyer cannot read administrative audit'
);
SELECT is(
    (SELECT count(*) FROM public.audit_log WHERE audit_scope = 'operational'),
    0::bigint,
    'W. administrative operations do not create operational audit rows'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000001');
SELECT ok(
    public.record_invite_audit('10000000-0000-0000-0000-000000000004', 'accepted') > 0,
    'X. owner can append an allowlisted invite audit event'
);
SELECT set_auth_user('10000000-0000-0000-0000-000000000002');
SELECT throws_ok(
    $$ SELECT public.record_invite_audit('10000000-0000-0000-0000-000000000004', 'accepted') $$,
    '42501',
    NULL,
    'Y. non-owner cannot append administrative audit'
);

SELECT set_auth_user('10000000-0000-0000-0000-000000000008');
SELECT ok(
    public.record_audit_export() > 0,
    'Z. auditor without owner can export administrative audit'
);
SELECT is(
    (SELECT metadata FROM public.get_administrative_audit(100, 'audit.export', 'audit_log') LIMIT 1),
    '{"reason": "csv"}'::jsonb,
    'AA. export audit stores only the allowlisted reason metadata'
);
SELECT set_auth_user('10000000-0000-0000-0000-000000000002');
SELECT throws_ok(
    $$ SELECT public.record_audit_export() $$,
    '42501',
    NULL,
    'AB. non-owner lawyer cannot export administrative audit'
);

SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{}', true);
SELECT throws_ok(
    $$ SELECT public.change_user_role('10000000-0000-0000-0000-000000000004', 'lawyer') $$,
    '42501',
    NULL,
    'AC. authenticated request without valid JWT subject is denied'
);
SELECT set_config('role', 'anon', true);
SELECT throws_ok(
    $$ SELECT public.change_user_role('10000000-0000-0000-0000-000000000004', 'lawyer') $$,
    '42501',
    NULL,
    'AD. anon cannot execute administrative RPC'
);
SELECT set_config('role', 'postgres', true);
SELECT is(
    (SELECT has_function_privilege('anon', 'public.change_user_role(uuid, public.user_role)', 'EXECUTE')),
    false,
    'AE. anon has no execute privilege on administrative RPC'
);

SELECT * FROM finish();
ROLLBACK;
