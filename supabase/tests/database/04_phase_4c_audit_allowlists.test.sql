BEGIN;

SELECT plan(16);

SELECT set_config('role', 'postgres', true);
INSERT INTO auth.users (id, email) VALUES
    ('40000000-0000-0000-0000-000000000001', 'allow-owner-a@test.local'),
    ('40000000-0000-0000-0000-000000000002', 'allow-owner-b@test.local'),
    ('40000000-0000-0000-0000-000000000003', 'allow-target@test.local'),
    ('40000000-0000-0000-0000-000000000004', 'allow-target-b@test.local');
INSERT INTO public.office (id, name, is_active) VALUES
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Allow Office A', true),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'Allow Office B', true);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES
    ('40000000-0000-0000-0000-000000000001', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Allow Owner A', 'lawyer', true, true),
    ('40000000-0000-0000-0000-000000000002', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'Allow Owner B', 'operator', true, true),
    ('40000000-0000-0000-0000-000000000003', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Allow Target A', 'operator', false, true),
    ('40000000-0000-0000-0000-000000000004', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'Allow Target B', 'operator', false, true);

-- 4. accepted audit com target NULL => DENY
SELECT throws_ok(
    $$ SELECT public.record_invite_audit_internal('40000000-0000-0000-0000-000000000001', NULL, 'accepted') $$,
    '22023',
    NULL,
    'A. accepted invite audit with NULL target is denied'
);

-- 5. accepted audit com reason não NULL => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_invite_audit_internal('40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003', 'accepted', 'auth_error') $$,
    '22023',
    NULL,
    'B. accepted invite audit with reason is denied'
);
SELECT set_config('role', 'postgres', true);

-- 6. accepted audit com target de outro office => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_invite_audit_internal('40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000004', 'accepted') $$,
    '22023',
    NULL,
    'C. accepted invite audit with cross-office target is denied'
);
SELECT set_config('role', 'postgres', true);

-- 7. rejected audit com reason desconhecida => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_invite_audit_internal('40000000-0000-0000-0000-000000000001', NULL, 'rejected', 'texto_livre_qualquer') $$,
    '22023',
    NULL,
    'D. rejected invite audit with unknown reason is denied'
);
SELECT set_config('role', 'postgres', true);

-- 8. rejection audit com action diferente de last_owner_blocked => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_rejection_audit_internal('40000000-0000-0000-0000-000000000001', 'generic_denial', 'user_profile', '40000000-0000-0000-0000-000000000003', 'deactivate_last_active_owner') $$,
    '22023',
    NULL,
    'E. rejection audit with unexpected action is denied'
);
SELECT set_config('role', 'postgres', true);

-- 9. rejection audit com entity_type diferente de user_profile => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_rejection_audit_internal('40000000-0000-0000-0000-000000000001', 'last_owner_blocked', 'office', '40000000-0000-0000-0000-000000000003', 'deactivate_last_active_owner') $$,
    '22023',
    NULL,
    'F. rejection audit with unexpected entity type is denied'
);
SELECT set_config('role', 'postgres', true);

-- 10. rejection audit com reason desconhecida (texto humano) => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_rejection_audit_internal('40000000-0000-0000-0000-000000000001', 'last_owner_blocked', 'user_profile', '40000000-0000-0000-0000-000000000003', 'Cannot deactivate last active owner') $$,
    '22023',
    NULL,
    'G. rejection audit with human-text reason is denied'
);
SELECT set_config('role', 'postgres', true);

-- 11. authenticated não tem EXECUTE nas internal functions
SELECT set_config('role', 'authenticated', true);
SELECT throws_ok(
    $$ SELECT public.record_invite_audit_internal('40000000-0000-0000-0000-000000000001', NULL, 'rejected', 'auth_error') $$,
    '42501',
    NULL,
    'H. authenticated cannot execute record_invite_audit_internal'
);
-- 12. anon não tem EXECUTE
SELECT set_config('role', 'anon', true);
SELECT throws_ok(
    $$ SELECT public.record_rejection_audit_internal('40000000-0000-0000-0000-000000000001', 'last_owner_blocked', 'user_profile', '40000000-0000-0000-0000-000000000003', 'deactivate_last_active_owner') $$,
    '42501',
    NULL,
    'I. anon cannot execute record_rejection_audit_internal'
);
SELECT set_config('role', 'postgres', true);

-- 13. service_role com actor inválido/inativo => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_invite_audit_internal('40000000-0000-0000-0000-000000000003', NULL, 'rejected', 'auth_error') $$,
    '42501',
    NULL,
    'J. non-owner actor is denied even under service_role'
);
SELECT throws_ok(
    $$ SELECT public.record_invite_audit_internal('00000000-0000-0000-0000-000000000099', NULL, 'rejected', 'auth_error') $$,
    '42501',
    NULL,
    'K. nonexistent actor is denied even under service_role'
);
SELECT set_config('role', 'postgres', true);

-- 14. service_role rejection com target cross-office => DENY
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ SELECT public.record_rejection_audit_internal('40000000-0000-0000-0000-000000000001', 'last_owner_blocked', 'user_profile', '40000000-0000-0000-0000-000000000004', 'deactivate_last_active_owner') $$,
    '22023',
    NULL,
    'L. rejection audit with cross-office target is denied'
);
SELECT set_config('role', 'postgres', true);

-- Happy paths (permitem confirmar que o endurecimento não fechou o fluxo real)
SELECT set_config('role', 'service_role', true);
SELECT is(
    (SELECT public.record_invite_audit_internal('40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003', 'accepted') IS NOT NULL),
    true,
    'M. accepted invite audit with valid same-office target succeeds'
);
SELECT is(
    (SELECT public.record_rejection_audit_internal('40000000-0000-0000-0000-000000000001', 'last_owner_blocked', 'user_profile', '40000000-0000-0000-0000-000000000003', 'revoke_last_active_owner') IS NOT NULL),
    true,
    'N. rejection audit with allowlisted machine reason succeeds'
);
SELECT set_config('role', 'postgres', true);

-- 15. audit_log continua append-only
SELECT set_config('role', 'service_role', true);
SELECT throws_ok(
    $$ UPDATE public.audit_log SET action = 'tampered' WHERE id = (SELECT min(id) FROM public.audit_log) $$,
    '42501',
    NULL,
    'O. audit_log UPDATE is denied'
);
SELECT throws_ok(
    $$ DELETE FROM public.audit_log WHERE id = (SELECT min(id) FROM public.audit_log) $$,
    '42501',
    NULL,
    'P. audit_log DELETE is denied'
);
SELECT set_config('role', 'postgres', true);

SELECT * FROM finish();
ROLLBACK;
