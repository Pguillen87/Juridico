begin;

insert into auth.users (id, email)
values
  ('70000000-0000-4000-8000-000000000001', 'phase5-lawyer@example.test'),
  ('70000000-0000-4000-8000-000000000002', 'phase5-operator@example.test'),
  ('70000000-0000-4000-8000-000000000003', 'phase5-reviewer@example.test'),
  ('70000000-0000-4000-8000-000000000004', 'phase5-auditor@example.test'),
  ('70000000-0000-4000-8000-000000000005', 'phase5-inactive@example.test'),
  ('70000000-0000-4000-8000-000000000006', 'phase5-cross-office@example.test')
on conflict do nothing;
insert into public.office (id, name, is_active)
values
  ('70000000-0000-4000-9000-000000000001', 'Phase 5 Office', true),
  ('70000000-0000-4000-9000-000000000002', 'Phase 5 Other Office', true),
  ('70000000-0000-4000-9000-000000000003', 'Phase 5 Inactive Office', false)
on conflict (id) do nothing;
insert into public.user_profile (id, office_id, name, role, is_owner, is_active)
values
  ('70000000-0000-4000-8000-000000000001', '70000000-0000-4000-9000-000000000001', 'Phase5 Lawyer', 'lawyer', false, true),
  ('70000000-0000-4000-8000-000000000002', '70000000-0000-4000-9000-000000000001', 'Phase5 Operator', 'operator', false, true),
  ('70000000-0000-4000-8000-000000000003', '70000000-0000-4000-9000-000000000001', 'Phase5 Reviewer', 'reviewer', false, true),
  ('70000000-0000-4000-8000-000000000004', '70000000-0000-4000-9000-000000000001', 'Phase5 Auditor', 'auditor', false, true),
  ('70000000-0000-4000-8000-000000000005', '70000000-0000-4000-9000-000000000001', 'Phase5 Inactive', 'operator', false, false),
  ('70000000-0000-4000-8000-000000000006', '70000000-0000-4000-9000-000000000002', 'Phase5 Other', 'lawyer', false, true)
on conflict (id) do nothing;
insert into public.party (id, office_id, party_type, display_name, normalized_name, created_by)
values
  ('70000000-0000-4000-a000-000000000001', '70000000-0000-4000-9000-000000000001', 'person', 'Phase 5 Client', 'phase 5 client', '70000000-0000-4000-8000-000000000001'),
  ('70000000-0000-4000-a000-000000000002', '70000000-0000-4000-9000-000000000001', 'person', 'Phase 5 Related', 'phase 5 related', '70000000-0000-4000-8000-000000000001'),
  ('70000000-0000-4000-a000-000000000003', '70000000-0000-4000-9000-000000000002', 'person', 'Phase 5 Other Party', 'phase 5 other party', '70000000-0000-4000-8000-000000000006')
on conflict (id) do nothing;
insert into public.client (id, office_id, party_id, created_by)
values ('70000000-0000-4000-b000-000000000001', '70000000-0000-4000-9000-000000000001', '70000000-0000-4000-a000-000000000001', '70000000-0000-4000-8000-000000000001')
on conflict (id) do nothing;

select plan(28);
select ok(has_table_privilege('authenticated', 'public.party', 'SELECT'), 'authenticated has SELECT grant for party');
select ok(has_table_privilege('authenticated', 'public.client', 'SELECT'), 'authenticated has SELECT grant for client');
select ok(has_table_privilege('authenticated', 'public.client_related_party', 'SELECT'), 'authenticated has SELECT grant for relation');
select ok(not has_table_privilege('authenticated', 'public.party', 'INSERT'), 'authenticated cannot INSERT party directly');
select ok(not has_table_privilege('authenticated', 'public.party', 'UPDATE'), 'authenticated cannot UPDATE party directly');
select ok(not has_table_privilege('authenticated', 'public.party', 'DELETE'), 'authenticated cannot DELETE party');
select ok(not has_table_privilege('authenticated', 'public.client', 'INSERT'), 'authenticated cannot INSERT client directly');
select ok(not has_table_privilege('authenticated', 'public.client', 'UPDATE'), 'authenticated cannot UPDATE client directly');
select ok(not has_table_privilege('authenticated', 'public.client', 'DELETE'), 'authenticated cannot DELETE client');
select ok(not has_table_privilege('authenticated', 'public.client_related_party', 'INSERT'), 'authenticated cannot INSERT relation directly');
select ok(not has_table_privilege('authenticated', 'public.client_related_party', 'UPDATE'), 'authenticated cannot UPDATE relation directly');
select ok(not has_table_privilege('authenticated', 'public.client_related_party', 'DELETE'), 'authenticated cannot DELETE relation');
select ok(not has_table_privilege('anon', 'public.party', 'SELECT'), 'anon has no party SELECT');
select ok(not has_function_privilege('anon', 'public.can_view_operational_row(uuid)'::regprocedure, 'EXECUTE'), 'anon cannot execute operational helper');
select ok(has_function_privilege('authenticated', 'public.can_view_operational_row(uuid)'::regprocedure, 'EXECUTE'), 'authenticated has only helper EXECUTE needed by RLS');

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
select is((select count(*)::integer from public.party), 2, 'lawyer sees only own office parties');
select is((select count(*)::integer from public.client), 1, 'lawyer sees own office clients');
select is((select count(*)::integer from public.party where office_id='70000000-0000-4000-9000-000000000002'), 0, 'cross-office party is not revealed');
select is((select count(*)::integer from public.client where office_id='70000000-0000-4000-9000-000000000002'), 0, 'cross-office client is not revealed');
select is((select count(*)::integer from public.party), 2, 'owner flag is not involved in operational SELECT');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000003', true);
select throws_ok($$select public.create_party('person', 'Reviewer must not mutate')$$, '42501', null, 'reviewer mutation is denied');
select lives_ok($$select count(*) from public.party$$, 'reviewer can read operational data');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000004', true);
select throws_ok($$select public.create_party('person', 'Auditor must not mutate')$$, '42501', null, 'auditor mutation is denied');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000005', true);
select is((select count(*)::integer from public.party), 0, 'inactive actor cannot read operational data');
reset role;

select throws_ok($$select public.create_client_related_party('70000000-0000-4000-b000-000000000001', '70000000-0000-4000-a000-000000000002', 'family_member', null)$$, '42501', null, 'unauthenticated domain call is denied');
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
select lives_ok($$select public.create_client_related_party('70000000-0000-4000-b000-000000000001', '70000000-0000-4000-a000-000000000002', 'family_member', null)$$, 'domain RPC creates relation for lawyer');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.create_client_related_party('70000000-0000-4000-b000-000000000001', '70000000-0000-4000-a000-000000000002', 'family_member', null)$$, '23505', null, 'active duplicate relation is rejected');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
select throws_ok($$insert into public.party (office_id, party_type, display_name, normalized_name, created_by) values ('70000000-0000-4000-9000-000000000001', 'person', 'Phase 5 Client', 'phase 5 client', '70000000-0000-4000-8000-000000000001')$$, '42501', null, 'direct party INSERT remains denied at executor boundary');
reset role;

select * from finish();
rollback;
