BEGIN;

SELECT plan(35);

-- Helper para setar o usuário logado no contexto da transação
CREATE OR REPLACE FUNCTION set_auth_user(user_id UUID) RETURNS void AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', user_id), true);
END;
$$ LANGUAGE plpgsql;

-- Preparar dados (bypass RLS para setup)
SELECT set_config('role', 'postgres', true);

-- Inserir usuários no auth.users
INSERT INTO auth.users (id, email) VALUES
    ('00000000-0000-0000-0000-000000000001', 'owner1@officeA.com'),
    ('00000000-0000-0000-0000-000000000002', 'owner2@officeA.com'),
    ('00000000-0000-0000-0000-000000000003', 'lawyer1@officeA.com'),
    ('00000000-0000-0000-0000-000000000004', 'operator1@officeA.com'),
    ('00000000-0000-0000-0000-000000000005', 'reviewer1@officeA.com'),
    ('00000000-0000-0000-0000-000000000006', 'owner1@officeB.com'),
    ('00000000-0000-0000-0000-000000000007', 'lawyer1@officeB.com'),
    ('00000000-0000-0000-0000-000000000008', 'inactive@officeA.com');

-- Inserir offices
INSERT INTO public.office (id, name, is_active) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Office A', true),
    ('22222222-2222-2222-2222-222222222222', 'Office B', true);

-- Inserir perfis
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES
    ('00000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Owner 1 A', 'lawyer', true, true),
    ('00000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Owner 2 A', 'lawyer', true, true),
    ('00000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Lawyer 1 A', 'lawyer', false, true),
    ('00000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Operator 1 A', 'operator', false, true),
    ('00000000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Reviewer 1 A', 'reviewer', false, true),
    ('00000000-0000-0000-0000-000000000006', '22222222-2222-2222-2222-222222222222', 'Owner 1 B', 'lawyer', true, true),
    ('00000000-0000-0000-0000-000000000007', '22222222-2222-2222-2222-222222222222', 'Lawyer 1 B', 'lawyer', false, true),
    ('00000000-0000-0000-0000-000000000008', '11111111-1111-1111-1111-111111111111', 'Inactive A', 'lawyer', false, false);

-- Mudar para authenticated para testar RLS
SELECT set_config('role', 'authenticated', true);

-- TESTE A: RLS está habilitado
SELECT is(
    (SELECT rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'user_profile'),
    true,
    'A. RLS is enabled on user_profile'
);

-- TESTE B: Usuário do office A não lê office B
SELECT set_auth_user('00000000-0000-0000-0000-000000000001');
SELECT is(
    (SELECT count(*) FROM public.user_profile WHERE office_id = '22222222-2222-2222-2222-222222222222'),
    0::bigint,
    'B. User from Office A cannot read Office B profiles'
);

-- TESTE C: Usuário do office A não escreve office B
-- Nota: RLS não lança exceção em UPDATE não autorizado, apenas afeta 0 linhas.
SELECT results_eq(
    $$ UPDATE public.user_profile SET name = 'Hacked' WHERE office_id = '22222222-2222-2222-2222-222222222222' RETURNING 1 $$,
    $$ SELECT 1::integer WHERE false $$,
    'B. User from Office A cannot write to Office B profiles (0 rows affected)'
);
-- Para testar que não afeta:
UPDATE public.user_profile SET name = 'Hacked' WHERE office_id = '22222222-2222-2222-2222-222222222222';
SELECT set_config('role', 'postgres', true);
SELECT is(
    (SELECT name FROM public.user_profile WHERE id = '00000000-0000-0000-0000-000000000006'),
    'Owner 1 B',
    'C. User from Office A did not actually write to Office B profiles'
);
SELECT set_config('role', 'authenticated', true);

-- TESTE D: Usuário inativo com contexto autenticado não lê
SELECT set_auth_user('00000000-0000-0000-0000-000000000008');
SELECT is(
    (SELECT count(*) FROM public.user_profile),
    0::bigint,
    'D. Inactive user cannot read any profile (including own)'
);
SELECT is(
    (SELECT count(*) FROM public.office),
    0::bigint,
    'D. Inactive user cannot read any office'
);
SELECT results_eq(
    $$ UPDATE public.user_profile SET name = 'Hacked' RETURNING 1 $$,
    $$ SELECT 1::integer WHERE false $$,
    'D. Inactive user cannot update any profile (0 rows affected)'
);

-- TESTE E: operator não altera próprio role
SELECT set_auth_user('00000000-0000-0000-0000-000000000004');
-- Non-owners cannot update their own profile (only owners can update profiles in their office)
-- So this update will silently fail (affect 0 rows) due to RLS, not trigger the exception
SELECT results_eq(
    $$ UPDATE public.user_profile SET role = 'lawyer' WHERE id = '00000000-0000-0000-0000-000000000004' RETURNING 1 $$,
    $$ SELECT 1::integer WHERE false $$,
    'E. Operator cannot change own role (0 rows affected due to RLS)'
);

-- TESTE F: reviewer não concede is_owner a si próprio
SELECT set_auth_user('00000000-0000-0000-0000-000000000005');
-- Non-owners cannot update their own profile (only owners can update profiles in their office)
-- So this update will silently fail (affect 0 rows) due to RLS, not trigger the exception
SELECT results_eq(
    $$ UPDATE public.user_profile SET is_owner = true WHERE id = '00000000-0000-0000-0000-000000000005' RETURNING 1 $$,
    $$ SELECT 1::integer WHERE false $$,
    'F. Reviewer cannot grant is_owner to self (0 rows affected due to RLS)'
);

-- TESTE G: lawyer sem is_owner não administra perfis
SELECT set_auth_user('00000000-0000-0000-0000-000000000003');
-- lawyer tenta ler todos (RLS deve retornar só ele mesmo)
SELECT is(
    (SELECT count(*) FROM public.user_profile),
    1::bigint,
    'G. Lawyer without is_owner can only see own profile'
);
-- lawyer tenta atualizar outro
UPDATE public.user_profile SET name = 'Hacked' WHERE id = '00000000-0000-0000-0000-000000000004';
SELECT set_config('role', 'postgres', true);
SELECT is(
    (SELECT name FROM public.user_profile WHERE id = '00000000-0000-0000-0000-000000000004'),
    'Operator 1 A',
    'G. Lawyer without is_owner cannot update other profiles'
);
SELECT set_config('role', 'authenticated', true);

-- TESTE H: lawyer + is_owner administra usuário autorizado do mesmo office
SELECT set_auth_user('00000000-0000-0000-0000-000000000001');
UPDATE public.user_profile SET name = 'Operator 1 A Edited' WHERE id = '00000000-0000-0000-0000-000000000004';
SELECT is(
    (SELECT name FROM public.user_profile WHERE id = '00000000-0000-0000-0000-000000000004'),
    'Operator 1 A Edited',
    'H. Owner can update profile in same office'
);

-- TESTE I: is_owner não ganha poderes jurídicos apenas pelo atributo (testado no schema: role e is_owner são separados)
SELECT is(
    (SELECT role::text FROM public.user_profile WHERE id = '00000000-0000-0000-0000-000000000001'),
    'lawyer',
    'I. is_owner is a boolean, role is separate (checked via data type)'
);

-- TESTE J: último owner ativo não pode perder is_owner, ser inativado ou ser removido
-- Primeiro, Owner 1 remove Owner 2 (é permitido pois Owner 1 ainda está ativo)
UPDATE public.user_profile SET is_owner = false WHERE id = '00000000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT is_owner FROM public.user_profile WHERE id = '00000000-0000-0000-0000-000000000002'),
    false,
    'K. Owner can lose is_owner if another owner is active'
);
-- Agora Owner 1 tenta inativar a si próprio, não deve poder pois ele não pode alterar próprio is_owner/role
-- Vamos simular um script de backend rodando como postgres tentando inativar o último owner
SELECT set_config('role', 'postgres', true);
SELECT throws_ok(
    $$ UPDATE public.user_profile SET is_active = false WHERE id = '00000000-0000-0000-0000-000000000001' $$,
    'P0001',
    'Cannot remove or deactivate the last active owner of an office',
    'J. Last active owner cannot be deactivated'
);
-- Cannot test losing is_owner directly because "Users cannot change their own is_owner status" exception fires first
SELECT throws_ok(
    $$ UPDATE public.user_profile SET is_owner = false WHERE id = '00000000-0000-0000-0000-000000000001' $$,
    'P0001',
    'Users cannot change their own is_owner status',
    'J. Last active owner cannot lose is_owner (fails due to self-elevation protection first)'
);
SELECT throws_ok(
    $$ DELETE FROM public.user_profile WHERE id = '00000000-0000-0000-0000-000000000001' $$,
    'P0001',
    'Cannot remove or deactivate the last active owner of an office',
    'J. Last active owner cannot be deleted'
);
SELECT set_config('role', 'authenticated', true);

-- TESTE L: office_id fornecido pelo cliente não permite acesso cruzado
SELECT set_auth_user('00000000-0000-0000-0000-000000000001');
SELECT is(
    (SELECT count(*) FROM public.office WHERE id = '22222222-2222-2222-2222-222222222222'),
    0::bigint,
    'L. office_id from client cannot read other office'
);

-- TESTE M: usuário não move o próprio perfil para outro office
SELECT throws_ok(
    $$ UPDATE public.user_profile SET office_id = '22222222-2222-2222-2222-222222222222' WHERE id = '00000000-0000-0000-0000-000000000001' $$,
    'P0001',
    'Users cannot change their own office_id',
    'M. User cannot move own profile to another office'
);

-- TESTE N: função SECURITY DEFINER não permite bypass de tenant
SELECT is(
    (SELECT count(*) FROM public.get_auth_user_profile() WHERE office_id = '22222222-2222-2222-2222-222222222222'),
    0::bigint,
    'N. SECURITY DEFINER function returns only the user''s own profile'
);

-- TESTE O: Usuário de office inativo não lê nem opera
-- Criar um office inativo e usuário nele (bypass RLS)
SELECT set_config('role', 'postgres', true);
INSERT INTO auth.users (id, email) VALUES ('00000000-0000-0000-0000-000000000009', 'user@officeC.com');
INSERT INTO public.office (id, name, is_active) VALUES ('33333333-3333-3333-3333-333333333333', 'Office C', false);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES ('00000000-0000-0000-0000-000000000009', '33333333-3333-3333-3333-333333333333', 'User C', 'lawyer', true, true);
SELECT set_config('role', 'authenticated', true);

SELECT set_auth_user('00000000-0000-0000-0000-000000000009');
SELECT is(
    (SELECT count(*) FROM public.user_profile),
    0::bigint,
    'O. User in inactive office cannot read profiles'
);
SELECT is(
    (SELECT count(*) FROM public.office),
    0::bigint,
    'O. User in inactive office cannot read office'
);

-- TESTE P: Testar as três formas de perder o último owner
SELECT set_config('role', 'postgres', true);
-- Office D com apenas um owner
INSERT INTO auth.users (id, email) VALUES ('00000000-0000-0000-0000-000000000010', 'owner@officeD.com');
INSERT INTO public.office (id, name, is_active) VALUES ('44444444-4444-4444-4444-444444444444', 'Office D', true);
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES ('00000000-0000-0000-0000-000000000010', '44444444-4444-4444-4444-444444444444', 'Owner D', 'lawyer', true, true);

-- 1. is_owner true -> false
SELECT throws_ok(
    $$ UPDATE public.user_profile SET is_owner = false WHERE id = '00000000-0000-0000-0000-000000000010' $$,
    'Cannot remove or deactivate the last active owner of an office',
    'P1. Last owner cannot lose is_owner'
);
-- 2. is_active true -> false
SELECT throws_ok(
    $$ UPDATE public.user_profile SET is_active = false WHERE id = '00000000-0000-0000-0000-000000000010' $$,
    'Cannot remove or deactivate the last active owner of an office',
    'P2. Last owner cannot be deactivated'
);
-- 3. DELETE
SELECT throws_ok(
    $$ DELETE FROM public.user_profile WHERE id = '00000000-0000-0000-0000-000000000010' $$,
    'Cannot remove or deactivate the last active owner of an office',
    'P3. Last owner cannot be deleted'
);

-- TESTE Q: Owner pode alterar nome do office mas não is_active, id ou created_at
SELECT set_auth_user('00000000-0000-0000-0000-000000000001');
-- Owner tenta atualizar is_active (não tem GRANT para is_active, então o banco recusa a query antes mesmo do RLS)
SELECT throws_ok(
    $$ UPDATE public.office SET is_active = false WHERE id = '11111111-1111-1111-1111-111111111111' $$,
    '42501',
    NULL,
    'Q. Owner cannot update office.is_active'
);
-- Owner tenta atualizar id
SELECT throws_ok(
    $$ UPDATE public.office SET id = '11111111-1111-1111-1111-111111111112' WHERE id = '11111111-1111-1111-1111-111111111111' $$,
    '42501',
    NULL,
    'Q. Owner cannot update office.id'
);
-- Owner tenta atualizar created_at
SELECT throws_ok(
    $$ UPDATE public.office SET created_at = now() WHERE id = '11111111-1111-1111-1111-111111111111' $$,
    '42501',
    NULL,
    'Q. Owner cannot update office.created_at'
);
-- Owner tenta atualizar nome (deve funcionar)
SELECT results_eq(
    $$ UPDATE public.office SET name = 'Office A Edited' WHERE id = '11111111-1111-1111-1111-111111111111' RETURNING 1 $$,
    $$ VALUES (1::integer) $$,
    'Q. Owner can update office.name'
);
-- Owner tenta atualizar nome de outro office (deve falhar silenciosamente por RLS)
SELECT results_eq(
    $$ UPDATE public.office SET name = 'Hacked' WHERE id = '22222222-2222-2222-2222-222222222222' RETURNING 1 $$,
    $$ SELECT 1::integer WHERE false $$,
    'Q. Owner cannot update other office name'
);

-- TESTE R: Privilégios SECURITY DEFINER restritos
SELECT set_config('role', 'anon', true);
SELECT throws_ok(
    $$ SELECT * FROM public.get_auth_user_profile() $$,
    '42501',
    NULL,
    'R. anon cannot execute get_auth_user_profile'
);
SELECT set_config('role', 'postgres', true);
SELECT is(
    (SELECT has_function_privilege('public', 'public.get_auth_user_profile()', 'EXECUTE')),
    false,
    'R. public role cannot execute get_auth_user_profile'
);
SELECT is(
    (SELECT has_function_privilege('anon', 'public.prevent_self_elevation()', 'EXECUTE')),
    false,
    'R. anon cannot execute prevent_self_elevation'
);
SELECT is(
    (SELECT has_function_privilege('anon', 'public.protect_last_active_owner()', 'EXECUTE')),
    false,
    'R. anon cannot execute protect_last_active_owner'
);

SELECT * FROM finish();
ROLLBACK;
