begin;

insert into auth.users (id, email)
values
  ('60000000-0000-4000-8000-000000000001', 'phase6-lawyer@example.test'),
  ('60000000-0000-4000-8000-000000000002', 'phase6-operator@example.test'),
  ('60000000-0000-4000-8000-000000000003', 'phase6-reviewer@example.test'),
  ('60000000-0000-4000-8000-000000000004', 'phase6-auditor@example.test'),
  ('60000000-0000-4000-8000-000000000005', 'phase6-other@example.test')
on conflict do nothing;
insert into public.office (id, name, is_active)
values
  ('60000000-0000-4000-9000-000000000001', 'Phase 6 Office', true),
  ('60000000-0000-4000-9000-000000000002', 'Phase 6 Other Office', true)
on conflict (id) do nothing;
insert into public.user_profile (id, office_id, name, role, is_owner, is_active)
values
  ('60000000-0000-4000-8000-000000000001', '60000000-0000-4000-9000-000000000001', 'Phase6 Lawyer', 'lawyer', false, true),
  ('60000000-0000-4000-8000-000000000002', '60000000-0000-4000-9000-000000000001', 'Phase6 Operator', 'operator', false, true),
  ('60000000-0000-4000-8000-000000000003', '60000000-0000-4000-9000-000000000001', 'Phase6 Reviewer', 'reviewer', false, true),
  ('60000000-0000-4000-8000-000000000004', '60000000-0000-4000-9000-000000000001', 'Phase6 Auditor', 'auditor', false, true),
  ('60000000-0000-4000-8000-000000000005', '60000000-0000-4000-9000-000000000002', 'Phase6 Other', 'lawyer', false, true)
on conflict (id) do nothing;
insert into public.party (id, office_id, party_type, display_name, normalized_name, created_by)
values
  ('60000000-0000-4000-a000-000000000001', '60000000-0000-4000-9000-000000000001', 'person', 'Phase 6 Client', 'phase 6 client', '60000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-a000-000000000002', '60000000-0000-4000-9000-000000000001', 'person', 'Phase 6 Party', 'phase 6 party', '60000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-a000-000000000003', '60000000-0000-4000-9000-000000000002', 'person', 'Phase 6 External Party', 'phase 6 external party', '60000000-0000-4000-8000-000000000005')
on conflict (id) do nothing;
insert into public.client (id, office_id, party_id, created_by)
values ('60000000-0000-4000-b000-000000000001', '60000000-0000-4000-9000-000000000001', '60000000-0000-4000-a000-000000000001', '60000000-0000-4000-8000-000000000001')
on conflict (id) do nothing;
insert into public.client (id, office_id, party_id, created_by)
values ('60000000-0000-4000-b000-000000000002', '60000000-0000-4000-9000-000000000002', '60000000-0000-4000-a000-000000000003', '60000000-0000-4000-8000-000000000005')
on conflict (id) do nothing;

select plan(43);
select is(public.normalize_cnj('0004453-12.2026.8.16.0000'), '00044531220268160000', 'CNJ is normalized without TJPR-only rejection');
select throws_ok($$select public.normalize_cnj('0004453-13.2026.8.16.0000')$$, '22023', null, 'invalid check digit is rejected DB-side');
select ok(has_table_privilege('authenticated', 'public.legal_process', 'SELECT'), 'authenticated can SELECT legal_process through RLS');
select ok(has_table_privilege('authenticated', 'public.process_party', 'SELECT'), 'authenticated can SELECT process_party through RLS');
select ok(not has_table_privilege('authenticated', 'public.legal_process', 'INSERT'), 'authenticated cannot INSERT legal_process directly');
select ok(not has_table_privilege('authenticated', 'public.legal_process', 'UPDATE'), 'authenticated cannot UPDATE legal_process directly');
select ok(not has_table_privilege('authenticated', 'public.legal_process', 'DELETE'), 'authenticated cannot DELETE legal_process directly');
select ok(not has_table_privilege('authenticated', 'public.process_party', 'INSERT'), 'authenticated cannot INSERT process_party directly');
select ok(not has_table_privilege('authenticated', 'public.process_party', 'UPDATE'), 'authenticated cannot UPDATE process_party directly');
select ok(not has_table_privilege('authenticated', 'public.process_party', 'DELETE'), 'authenticated cannot DELETE process_party directly');
select ok(not has_table_privilege('authenticated', 'public.process_import_preview', 'SELECT'), 'authenticated cannot SELECT private preview directly');
select ok(has_function_privilege('authenticated', 'public.create_legal_process(uuid,text,text,text,boolean)'::regprocedure, 'EXECUTE'), 'authenticated can execute process domain RPC');
select ok(has_function_privilege('authenticated', 'public.create_process_party(uuid,uuid,text,text,text)'::regprocedure, 'EXECUTE'), 'authenticated can execute process_party creation RPC');
select ok(not has_function_privilege('authenticated', 'public.phase6_validate_import_rows(jsonb,uuid)'::regprocedure, 'EXECUTE'), 'internal import validator is closed');
select ok(not has_function_privilege('authenticated', 'public.write_operational_audit(text,text,uuid,jsonb)'::regprocedure, 'EXECUTE'), 'operational audit helper is closed');

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.create_legal_process('60000000-0000-4000-b000-000000000001', '0004453-13.2026.8.16.0000', 'TJPR', 'PJe', true)$$, '22023', null, 'invalid CNJ cannot create process');
select ok((select public.create_legal_process('60000000-0000-4000-b000-000000000001', '0004453-12.2026.8.16.0000', 'TJPR', 'PJe', true) is not null), 'lawyer creates process through RPC');
select is((select monitoring_status from public.legal_process where cnj_number = '00044531220268160000'), 'paused', 'new process starts paused');
select throws_ok($$insert into public.legal_process(office_id, client_id, cnj_number, tribunal, created_by) values ('60000000-0000-4000-9000-000000000001', '60000000-0000-4000-b000-000000000001', '00044531220268160001', 'TJPR', '60000000-0000-4000-8000-000000000001')$$, '42501', null, 'direct legal_process INSERT is denied');
select throws_ok($$insert into public.process_party(office_id, process_id, party_id, role_in_process, source, created_by) values ('60000000-0000-4000-9000-000000000001', (select id from public.legal_process where cnj_number = '00044531220268160000'), '60000000-0000-4000-a000-000000000002', 'plaintiff', 'manual', '60000000-0000-4000-8000-000000000001')$$, '42501', null, 'direct process_party INSERT is denied');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000002', true);
select lives_ok($$select public.create_legal_process('60000000-0000-4000-b000-000000000001', '0008569-61.2026.8.16.0000', 'TJPR', 'PJe', true)$$, 'operator creates process through RPC');
select lives_ok($$select public.create_process_party((select id from public.legal_process where cnj_number = '00085696120268160000'), '60000000-0000-4000-a000-000000000002', 'defendant', 'manual', null)$$, 'operator creates process_party through RPC');
select is((select confirmation_status from public.process_party order by created_at desc limit 1), 'pending', 'operator-created process_party is always pending');
select is((select confirmed_by from public.process_party order by created_at desc limit 1), null::uuid, 'created process_party has no confirmed_by');
select is((select confirmed_at from public.process_party order by created_at desc limit 1), null::timestamptz, 'created process_party has no confirmed_at');
select throws_ok($$select public.confirm_process_party((select id from public.process_party order by created_at desc limit 1))$$, '42501', null, 'operator cannot confirm process_party');
select throws_ok($$select public.create_process_party((select id from public.legal_process where cnj_number = '00085696120268160000'), '60000000-0000-4000-a000-000000000002', 'defendant', 'manual', null)$$, '23505', null, 'active process_party duplicate is rejected');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000003', true);
select lives_ok($$select count(*) from public.legal_process$$, 'reviewer can read own office process');
select throws_ok($$select public.create_process_party((select id from public.legal_process order by created_at limit 1), '60000000-0000-4000-a000-000000000002', 'other', 'manual', null)$$, '42501', null, 'reviewer cannot create process_party');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
select lives_ok($$select public.confirm_process_party((select id from public.process_party order by created_at desc limit 1))$$, 'lawyer can confirm pending process_party');
select is((select confirmation_status from public.process_party order by created_at desc limit 1), 'confirmed', 'lawyer confirmation is terminal and explicit');
reset role;
select ok((select count(*)::integer from public.audit_log where action = 'process_party.confirmed' and entity_type = 'process_party') >= 1, 'confirmation writes audit event');
set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
select throws_ok($$select public.confirm_process_party((select id from public.process_party order by created_at desc limit 1))$$, 'P0001', null, 'terminal process_party cannot be confirmed twice');

select lives_ok($$select public.create_legal_process('60000000-0000-4000-b000-000000000001', '0002557-31.2026.8.16.0000', 'TJPR', 'PJe', true)$$, 'lawyer creates second process for preview baseline');
create temporary table phase6_preview_id (id uuid);
insert into phase6_preview_id
select preview_id from public.preview_process_import(jsonb_build_array(jsonb_build_object('cnj_number','0003907-54.2026.8.16.0000','client_id','60000000-0000-4000-b000-000000000001','tribunal','TJPR','system','PJe','party_id',null,'role_in_process',null,'is_public',true,'monitoring_status','paused','notes',null,'source','csv')), repeat('a',64), 'phase6-csv-v1', jsonb_build_object('total_rows',1));
select ok((select count(*)::integer from phase6_preview_id) = 1, 'lawyer creates private preview');
select is((select count(*)::integer from public.legal_process where cnj_number = '00039075420268160000'), 0, 'preview does not create legal_process');
select lives_ok($$select public.confirm_process_import((select id from phase6_preview_id))$$, 'preview confirm persists in one domain operation');
select is((select count(*)::integer from public.legal_process where cnj_number = '00039075420268160000'), 1, 'confirmed preview creates legal_process');
select is((select status from public.get_process_import_preview((select id from phase6_preview_id))), 'consumed', 'preview is consumed atomically');
reset role;
select ok((select count(*)::integer from public.audit_log where action = 'process.imported') >= 1, 'import writes process.imported audit event');
set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-4000-8000-000000000001', true);
select lives_ok($$select public.confirm_process_import((select id from phase6_preview_id))$$, 'consuming preview twice is idempotent');
select is((select count(*)::integer from public.legal_process where cnj_number = '00039075420268160000'), 1, 'replayed preview does not duplicate process');
select throws_ok($$select public.create_process_party((select id from public.legal_process where cnj_number = '00025573120268160000'), '60000000-0000-4000-a000-000000000003', 'plaintiff', 'manual', null)$$, 'P0002', null, 'cross-office party reference is denied');
reset role;

select * from finish();
rollback;
