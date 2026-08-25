begin;

insert into auth.users (id, email)
values ('80000000-0000-4000-8000-000000000001', 'phase5-rollback-lawyer@example.test')
on conflict do nothing;
insert into public.office (id, name, is_active)
values ('80000000-0000-4000-9000-000000000001', 'Phase 5 Rollback Office', true)
on conflict do nothing;
insert into public.user_profile (id, office_id, name, role, is_owner, is_active)
values ('80000000-0000-4000-8000-000000000001', '80000000-0000-4000-9000-000000000001', 'Rollback Lawyer', 'lawyer', true, true)
on conflict (id) do nothing;
insert into public.party (id, office_id, party_type, display_name, normalized_name, created_by)
values
  ('80000000-0000-4000-a000-000000000001', '80000000-0000-4000-9000-000000000001', 'person', 'Rollback Client', 'rollback client', '80000000-0000-4000-8000-000000000001'),
  ('80000000-0000-4000-a000-000000000002', '80000000-0000-4000-9000-000000000001', 'person', 'Rollback Related', 'rollback related', '80000000-0000-4000-8000-000000000001'),
  ('80000000-0000-4000-a000-000000000003', '80000000-0000-4000-9000-000000000001', 'person', 'Rollback Free Party', 'rollback free party', '80000000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into public.client (id, office_id, party_id, created_by)
values ('80000000-0000-4000-b000-000000000001', '80000000-0000-4000-9000-000000000001', '80000000-0000-4000-a000-000000000001', '80000000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into public.client_related_party (id, office_id, client_id, party_id, relation_type, created_by)
values ('80000000-0000-4000-c000-000000000001', '80000000-0000-4000-9000-000000000001', '80000000-0000-4000-b000-000000000001', '80000000-0000-4000-a000-000000000002', 'representative', '80000000-0000-4000-8000-000000000001')
on conflict (id) do nothing;

create or replace function pg_temp.fail_phase5_audit() returns trigger
language plpgsql as $$
begin
  if new.audit_scope = 'operational'
     and current_setting('phase5.test_pid', true) = pg_backend_pid()::text then
    raise exception 'controlled audit failure' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger phase5_test_fail_audit before insert on public.audit_log
for each row when (current_setting('phase5.test_pid', true) = pg_backend_pid()::text)
execute function pg_temp.fail_phase5_audit();

create temporary table phase5_audit_baseline as
select coalesce(max(id), 0)::bigint as max_id
from public.audit_log;

select plan(9);
select set_config('phase5.test_pid', pg_backend_pid()::text, false);

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.create_party('person', 'Rollback Created Party')$$, 'P0001', null, 'createParty fails when audit insert fails');
reset role;
select is((select count(*)::integer from public.party where display_name='Rollback Created Party'), 0, 'createParty domain row rolled back');
select is((select count(*)::integer
            from public.audit_log l
            where l.id > (select max_id from phase5_audit_baseline)
              and l.entity_type='party'
              and l.metadata @> '{"after":{"status":"active"}}'),
           0,
           'createParty leaves no partial audit');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.create_client_related_party('80000000-0000-4000-b000-000000000001', '80000000-0000-4000-a000-000000000003', 'representative', null)$$, 'P0001', null, 'addClientRelatedParty fails when audit insert fails');
reset role;
select is((select count(*)::integer from public.client_related_party where party_id='80000000-0000-4000-a000-000000000003'), 0, 'addClientRelatedParty relation row rolled back');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.confirm_client_related_party('80000000-0000-4000-c000-000000000001')$$, 'P0001', null, 'confirmRelatedParty fails when audit insert fails');
reset role;
select is((select confirmation_status from public.client_related_party where id='80000000-0000-4000-c000-000000000001'), 'pending', 'confirmRelatedParty status update rolled back');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.deactivate_party('80000000-0000-4000-a000-000000000003')$$, 'P0001', null, 'deactivateParty fails when audit insert fails');
reset role;
select is((select status from public.party where id='80000000-0000-4000-a000-000000000003'), 'active', 'deactivateParty status update rolled back');

select * from finish();
rollback;

