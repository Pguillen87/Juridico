set lock_timeout = '2s';

drop policy if exists legal_process_select_same_office on public.legal_process;
drop policy if exists process_party_select_same_office on public.process_party;

create policy legal_process_select_same_office
on public.legal_process
for select to authenticated
using (public.can_view_operational_row(office_id));

create policy process_party_select_same_office
on public.process_party
for select to authenticated
using (public.can_view_operational_row(office_id));
