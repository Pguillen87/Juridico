begin;

insert into auth.users (id, email)
values
  ('61000000-0000-4000-8000-000000000001', 'phase6-rls-lawyer@example.test'),
  ('61000000-0000-4000-8000-000000000002', 'phase6-rls-reviewer@example.test'),
  ('61000000-0000-4000-8000-000000000003', 'phase6-rls-auditor@example.test'),
  ('61000000-0000-4000-8000-000000000004', 'phase6-rls-owner-auditor@example.test'),
  ('61000000-0000-4000-8000-000000000005', 'phase6-rls-inactive@example.test')
on conflict do nothing;
insert into public.office (id, name, is_active)
values
  ('61000000-0000-4000-9000-000000000001', 'Phase 6 RLS Office', true),
  ('61000000-0000-4000-9000-000000000002', 'Phase 6 RLS Inactive Office', false)
on conflict (id) do update set is_active = excluded.is_active;
insert into public.user_profile (id, office_id, name, role, is_owner, is_active)
values
  ('61000000-0000-4000-8000-000000000001', '61000000-0000-4000-9000-000000000001', 'RLS Lawyer', 'lawyer', false, true),
  ('61000000-0000-4000-8000-000000000002', '61000000-0000-4000-9000-000000000001', 'RLS Reviewer', 'reviewer', false, true),
  ('61000000-0000-4000-8000-000000000003', '61000000-0000-4000-9000-000000000001', 'RLS Auditor', 'auditor', false, true),
  ('61000000-0000-4000-8000-000000000004', '61000000-0000-4000-9000-000000000001', 'RLS Owner Auditor', 'auditor', true, true),
  ('61000000-0000-4000-8000-000000000005', '61000000-0000-4000-9000-000000000002', 'RLS Inactive Office User', 'reviewer', false, true)
on conflict (id) do update set office_id = excluded.office_id, role = excluded.role, is_owner = excluded.is_owner, is_active = excluded.is_active;
insert into public.party (id, office_id, party_type, display_name, normalized_name, created_by)
values
  ('61000000-0000-4000-a000-000000000001', '61000000-0000-4000-9000-000000000001', 'person', 'RLS Client', 'rls client', '61000000-0000-4000-8000-000000000001'),
  ('61000000-0000-4000-a000-000000000002', '61000000-0000-4000-9000-000000000002', 'person', 'RLS Inactive Party', 'rls inactive party', '61000000-0000-4000-8000-000000000005')
on conflict (id) do nothing;
insert into public.client (id, office_id, party_id, created_by)
values
  ('61000000-0000-4000-b000-000000000001', '61000000-0000-4000-9000-000000000001', '61000000-0000-4000-a000-000000000001', '61000000-0000-4000-8000-000000000001'),
  ('61000000-0000-4000-b000-000000000002', '61000000-0000-4000-9000-000000000002', '61000000-0000-4000-a000-000000000002', '61000000-0000-4000-8000-000000000005')
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000001', true);
select public.create_legal_process('61000000-0000-4000-b000-000000000001', '0004453-12.2026.8.16.0000', 'TJPR', 'PJe', true);
select public.create_process_party((select id from public.legal_process where office_id = '61000000-0000-4000-9000-000000000001' and cnj_number = '00044531220268160000'), '61000000-0000-4000-a000-000000000001', 'plaintiff', 'manual', null);
reset role;

insert into public.legal_process (id, office_id, client_id, cnj_number, tribunal, system, is_public, monitoring_status, status, created_by)
values ('61000000-0000-4000-c000-000000000001', '61000000-0000-4000-9000-000000000002', '61000000-0000-4000-b000-000000000002', '00085696120268160000', 'TJPR', 'PJe', true, 'paused', 'active', '61000000-0000-4000-8000-000000000005')
on conflict (id) do nothing;
insert into public.process_party (id, office_id, process_id, party_id, role_in_process, source, confirmation_status, status, created_by)
values ('61000000-0000-4000-d000-000000000001', '61000000-0000-4000-9000-000000000002', '61000000-0000-4000-c000-000000000001', '61000000-0000-4000-a000-000000000002', 'plaintiff', 'manual', 'pending', 'active', '61000000-0000-4000-8000-000000000005')
on conflict (id) do nothing;
insert into public.process_import_preview (id, office_id, created_by, content_hash, parser_version, normalized_rows, summary, expires_at, status)
values ('61000000-0000-4000-e000-000000000001', '61000000-0000-4000-9000-000000000001', '61000000-0000-4000-8000-000000000001', repeat('e', 64), 'phase6-csv-v1', '[]'::jsonb, '{}'::jsonb, now() - interval '1 minute', 'pending')
on conflict (id) do nothing;

select plan(12);

set local role authenticated;
select set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000002', true);
select is((select count(*)::integer from public.legal_process where office_id = '61000000-0000-4000-9000-000000000001'), 1, 'reviewer sees own-office process through RLS');
select is((select count(*)::integer from public.process_party where office_id = '61000000-0000-4000-9000-000000000001'), 1, 'reviewer sees own-office relation through RLS');
select is((select count(*)::integer from public.legal_process where office_id = '61000000-0000-4000-9000-000000000002'), 0, 'reviewer cannot see cross-office process rows');
select is((select count(*)::integer from public.process_party where office_id = '61000000-0000-4000-9000-000000000002'), 0, 'reviewer cannot see cross-office relation rows');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000003', true);
select is((select count(*)::integer from public.legal_process), 0, 'auditor sees zero operational process rows');
select is((select count(*)::integer from public.process_party), 0, 'auditor sees zero operational relation rows');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000004', true);
select is((select count(*)::integer from public.legal_process), 0, 'owner auditor remains denied operational process rows');
select is((select count(*)::integer from public.process_party), 0, 'owner auditor remains denied operational relation rows');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000005', true);
select is((select count(*)::integer from public.legal_process), 0, 'user of inactive office cannot see process rows');
select is((select count(*)::integer from public.process_party), 0, 'user of inactive office cannot see relation rows');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.confirm_process_import('61000000-0000-4000-e000-000000000001')$$, 'P0001', null, 'expired preview is rejected');
select is((select status from public.get_process_import_preview('61000000-0000-4000-e000-000000000001')), 'pending', 'expired preview remains pending after rejected transaction');
reset role;

select * from finish();
rollback;
