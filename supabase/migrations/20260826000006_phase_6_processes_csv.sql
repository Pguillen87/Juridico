create or replace function public.normalize_cnj(p_cnj text)
returns text
language plpgsql
immutable
security invoker
set search_path = pg_catalog
as $$
declare
  clean text := regexp_replace(coalesce(p_cnj, ''), '[^0-9]', '', 'g');
  base text;
  expected text;
  actual text;
begin
  if length(clean) <> 20 then
    raise exception 'invalid CNJ: expected 20 digits' using errcode = '22023';
  end if;

  base := substr(clean, 1, 7) || substr(clean, 10, 11);
  expected := lpad((98 - mod((base || '00')::numeric, 97))::text, 2, '0');
  actual := substr(clean, 8, 2);
  if actual <> expected then
    raise exception 'invalid CNJ: check digits do not match' using errcode = '22023';
  end if;

  return clean;
end;
$$;

create table public.legal_process (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references public.office(id) on delete restrict,
  client_id uuid not null,
  cnj_number text not null check (cnj_number ~ '^[0-9]{20}$'),
  tribunal text not null check (char_length(btrim(tribunal)) between 2 and 200),
  system text check (system is null or char_length(btrim(system)) between 2 and 120),
  is_public boolean not null default true,
  monitoring_status text not null default 'paused' check (monitoring_status = 'paused'),
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references public.user_profile(id) on delete restrict,
  unique (office_id, id),
  unique (office_id, cnj_number),
  foreign key (office_id, client_id) references public.client(office_id, id) on delete restrict
);

create index legal_process_client_idx on public.legal_process(office_id, client_id, status);
create index legal_process_status_idx on public.legal_process(office_id, status);
create index legal_process_monitoring_idx on public.legal_process(office_id, monitoring_status);

create table public.process_party (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references public.office(id) on delete restrict,
  process_id uuid not null,
  party_id uuid not null,
  role_in_process text not null check (role_in_process in ('client', 'plaintiff', 'defendant', 'representative', 'interested_party', 'other')),
  source text not null check (source in ('manual', 'csv')),
  confirmation_status text not null default 'pending' check (confirmation_status in ('pending', 'confirmed', 'rejected')),
  confirmed_by uuid references public.user_profile(id) on delete restrict,
  confirmed_at timestamptz,
  notes text check (notes is null or char_length(notes) <= 1000),
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null references public.user_profile(id) on delete restrict,
  unique (office_id, id),
  foreign key (office_id, process_id) references public.legal_process(office_id, id) on delete restrict,
  foreign key (office_id, party_id) references public.party(office_id, id) on delete restrict,
  check (
    (confirmation_status = 'pending' and confirmed_by is null and confirmed_at is null)
    or (confirmation_status in ('confirmed', 'rejected') and confirmed_by is not null and confirmed_at is not null)
  )
);

create unique index process_party_active_idx
  on public.process_party(office_id, process_id, party_id, role_in_process)
  where status = 'active';
create index process_party_process_idx on public.process_party(office_id, process_id, status);
create index process_party_party_idx on public.process_party(office_id, party_id, status);

create table public.process_import_preview (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references public.office(id) on delete restrict,
  created_by uuid not null references public.user_profile(id) on delete restrict,
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  parser_version text not null check (char_length(btrim(parser_version)) between 1 and 80),
  normalized_rows jsonb not null check (jsonb_typeof(normalized_rows) = 'array'),
  summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  status text not null default 'pending' check (status in ('pending', 'consumed', 'expired')),
  consumed_at timestamptz,
  consumed_summary jsonb,
  check ((status = 'consumed' and consumed_at is not null) or status <> 'consumed')
);

create index process_import_preview_owner_idx on public.process_import_preview(office_id, created_by, status, expires_at);

create or replace function public.write_operational_audit(
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  aid bigint;
begin
  select * into a from public.require_active_actor();
  if p_action not in (
    'client.created', 'client.updated', 'client.deactivated',
    'party.created', 'party.updated', 'party.deactivated',
    'client_related_party.created', 'client_related_party.updated',
    'client_related_party.confirmed', 'client_related_party.rejected',
    'client_related_party.deactivated',
    'process.created', 'process.updated', 'process.deactivated',
    'process_party.created', 'process_party.confirmed',
    'process_party.rejected', 'process_party.deactivated', 'process.imported'
  ) then
    raise exception 'audit action is not allowlisted' using errcode = '22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'invalid audit metadata' using errcode = '22023';
  end if;
  insert into public.audit_log(audit_scope, office_id, actor_user_id, action, entity_type, entity_id, metadata)
  values ('operational', a.actor_office_id, a.actor_id, p_action, p_entity_type, p_entity_id, p_metadata)
  returning id into aid;
  return aid;
end;
$$;

create or replace function public.phase6_validate_import_rows(
  p_rows jsonb,
  p_office_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  row_data jsonb;
  client_uuid uuid;
  party_uuid uuid;
  normalized_cnj text;
  row_role text;
  row_source text;
  row_tribunal text;
  row_system text;
  row_notes text;
  row_monitoring text;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) < 1 or jsonb_array_length(p_rows) > 1000 then
    raise exception 'invalid import rows' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_rows) as entries(value)
    group by value ->> 'cnj_number'
    having count(*) > 1
  ) then
    raise exception 'duplicate CNJ in import' using errcode = '23505';
  end if;

  for row_data in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(row_data) <> 'object' then
      raise exception 'invalid import row' using errcode = '22023';
    end if;
    normalized_cnj := public.normalize_cnj(row_data ->> 'cnj_number');
    client_uuid := (row_data ->> 'client_id')::uuid;
    row_tribunal := btrim(coalesce(row_data ->> 'tribunal', ''));
    row_system := nullif(btrim(row_data ->> 'system'), '');
    row_role := nullif(btrim(row_data ->> 'role_in_process'), '');
    row_source := coalesce(row_data ->> 'source', 'csv');
    row_notes := nullif(row_data ->> 'notes', '');
    row_monitoring := coalesce(row_data ->> 'monitoring_status', 'paused');

    if row_tribunal = '' or length(row_tribunal) > 200 or (row_system is not null and length(row_system) > 120) then
      raise exception 'invalid import row fields' using errcode = '22023';
    end if;
    if row_source <> 'csv' or row_monitoring <> 'paused' then
      raise exception 'invalid import source or monitoring state' using errcode = '22023';
    end if;
    if row_notes is not null and length(row_notes) > 1000 then
      raise exception 'invalid import notes' using errcode = '22023';
    end if;
    if row_role is not null and row_role not in ('client', 'plaintiff', 'defendant', 'representative', 'interested_party', 'other') then
      raise exception 'invalid process party role' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.client c
      where c.office_id = p_office_id and c.id = client_uuid and c.status = 'active'
    ) then
      raise exception 'client not found' using errcode = 'P0002';
    end if;
    if exists (select 1 from public.legal_process lp where lp.office_id = p_office_id and lp.cnj_number = normalized_cnj) then
      raise exception 'duplicate CNJ in office' using errcode = '23505';
    end if;

    if nullif(row_data ->> 'party_id', '') is not null then
      party_uuid := (row_data ->> 'party_id')::uuid;
      if row_role is null then
        raise exception 'process party role is required' using errcode = '22023';
      end if;
      if not exists (
        select 1 from public.party p
        where p.office_id = p_office_id and p.id = party_uuid and p.status = 'active'
      ) then
        raise exception 'party not found' using errcode = 'P0002';
      end if;
    end if;
  end loop;
end;
$$;

create or replace function public.create_legal_process(
  p_client_id uuid,
  p_cnj_number text,
  p_tribunal text,
  p_system text default null,
  p_is_public boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  process_id uuid;
  normalized_cnj text;
  old_system text := nullif(btrim(p_system), '');
  tribunal_name text := btrim(coalesce(p_tribunal, ''));
begin
  select * into a from public.require_active_actor();
  if a.actor_role not in ('lawyer', 'operator') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  normalized_cnj := public.normalize_cnj(p_cnj_number);
  if tribunal_name = '' or length(tribunal_name) > 200 or (old_system is not null and length(old_system) > 120) then
    raise exception 'invalid process input' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.client c
    where c.office_id = a.actor_office_id and c.id = p_client_id and c.status = 'active'
  ) then
    raise exception 'client not found' using errcode = 'P0002';
  end if;
  insert into public.legal_process(office_id, client_id, cnj_number, tribunal, system, is_public, monitoring_status, status, created_by)
  values (a.actor_office_id, p_client_id, normalized_cnj, tribunal_name, old_system, coalesce(p_is_public, true), 'paused', 'active', a.actor_id)
  returning id into process_id;
  perform public.write_operational_audit('process.created', 'legal_process', process_id,
    jsonb_build_object('after', jsonb_build_object('cnj_number', normalized_cnj, 'client_id', p_client_id, 'is_public', coalesce(p_is_public, true), 'monitoring_status', 'paused', 'status', 'active')));
  return process_id;
end;
$$;

create or replace function public.update_legal_process(
  p_id uuid,
  p_cnj_number text,
  p_tribunal text,
  p_system text default null,
  p_is_public boolean default true
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  old_row public.legal_process%rowtype;
  normalized_cnj text;
  old_system text := nullif(btrim(p_system), '');
  tribunal_name text := btrim(coalesce(p_tribunal, ''));
begin
  select * into a from public.require_active_actor();
  if a.actor_role not in ('lawyer', 'operator') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select * into old_row from public.legal_process where id = p_id and office_id = a.actor_office_id for update;
  if old_row.id is null or old_row.status <> 'active' then
    raise exception 'process not found or inactive' using errcode = 'P0002';
  end if;
  normalized_cnj := public.normalize_cnj(p_cnj_number);
  if tribunal_name = '' or length(tribunal_name) > 200 or (old_system is not null and length(old_system) > 120) then
    raise exception 'invalid process input' using errcode = '22023';
  end if;
  update public.legal_process
  set cnj_number = normalized_cnj, tribunal = tribunal_name, system = old_system, is_public = coalesce(p_is_public, true), updated_at = now()
  where id = p_id and office_id = a.actor_office_id;
  perform public.write_operational_audit('process.updated', 'legal_process', p_id,
    jsonb_build_object('before', jsonb_build_object('cnj_number', old_row.cnj_number, 'tribunal', old_row.tribunal, 'system', old_row.system, 'is_public', old_row.is_public),
                       'after', jsonb_build_object('cnj_number', normalized_cnj, 'tribunal', tribunal_name, 'system', old_system, 'is_public', coalesce(p_is_public, true))));
end;
$$;

create or replace function public.deactivate_legal_process(p_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
begin
  select * into a from public.require_active_actor();
  if a.actor_role not in ('lawyer', 'operator') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  update public.legal_process set status = 'inactive', updated_at = now()
  where id = p_id and office_id = a.actor_office_id and status = 'active';
  if not found then
    raise exception 'process not found or inactive' using errcode = 'P0002';
  end if;
  perform public.write_operational_audit('process.deactivated', 'legal_process', p_id,
    jsonb_build_object('after', jsonb_build_object('status', 'inactive')));
end;
$$;

create or replace function public.create_process_party(
  p_process_id uuid,
  p_party_id uuid,
  p_role_in_process text,
  p_source text default 'manual',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  relation_id uuid;
  role_name text := nullif(btrim(p_role_in_process), '');
  source_name text := coalesce(p_source, 'manual');
begin
  select * into a from public.require_active_actor();
  if a.actor_role not in ('lawyer', 'operator') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  if role_name not in ('client', 'plaintiff', 'defendant', 'representative', 'interested_party', 'other') or source_name not in ('manual', 'csv') then
    raise exception 'invalid process party input' using errcode = '22023';
  end if;
  if p_notes is not null and length(p_notes) > 1000 then
    raise exception 'invalid process party notes' using errcode = '22023';
  end if;
  if not exists (select 1 from public.legal_process lp where lp.office_id = a.actor_office_id and lp.id = p_process_id and lp.status = 'active') then
    raise exception 'process not found or inactive' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.party p where p.office_id = a.actor_office_id and p.id = p_party_id and p.status = 'active') then
    raise exception 'party not found' using errcode = 'P0002';
  end if;
  insert into public.process_party(office_id, process_id, party_id, role_in_process, source, confirmation_status, confirmed_by, confirmed_at, notes, status, created_by)
  values (a.actor_office_id, p_process_id, p_party_id, role_name, source_name, 'pending', null, null, p_notes, 'active', a.actor_id)
  returning id into relation_id;
  perform public.write_operational_audit('process_party.created', 'process_party', relation_id,
    jsonb_build_object('after', jsonb_build_object('process_id', p_process_id, 'party_id', p_party_id, 'role_in_process', role_name, 'source', source_name, 'confirmation_status', 'pending', 'status', 'active')));
  return relation_id;
end;
$$;

create or replace function public.confirm_process_party(p_relation_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  r public.process_party%rowtype;
begin
  select * into a from public.require_active_actor();
  if a.actor_role <> 'lawyer' then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select * into r from public.process_party where id = p_relation_id and office_id = a.actor_office_id for update;
  if r.id is null or r.status <> 'active' or r.confirmation_status <> 'pending' then
    raise exception 'invalid transition' using errcode = 'P0001';
  end if;
  update public.process_party set confirmation_status = 'confirmed', confirmed_by = a.actor_id, confirmed_at = now(), updated_at = now()
  where id = r.id;
  perform public.write_operational_audit('process_party.confirmed', 'process_party', r.id,
    jsonb_build_object('before', jsonb_build_object('confirmation_status', 'pending'), 'after', jsonb_build_object('confirmation_status', 'confirmed')));
end;
$$;

create or replace function public.reject_process_party(p_relation_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  r public.process_party%rowtype;
begin
  select * into a from public.require_active_actor();
  if a.actor_role <> 'lawyer' then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select * into r from public.process_party where id = p_relation_id and office_id = a.actor_office_id for update;
  if r.id is null or r.status <> 'active' or r.confirmation_status <> 'pending' then
    raise exception 'invalid transition' using errcode = 'P0001';
  end if;
  update public.process_party set confirmation_status = 'rejected', confirmed_by = a.actor_id, confirmed_at = now(), updated_at = now()
  where id = r.id;
  perform public.write_operational_audit('process_party.rejected', 'process_party', r.id,
    jsonb_build_object('before', jsonb_build_object('confirmation_status', 'pending'), 'after', jsonb_build_object('confirmation_status', 'rejected')));
end;
$$;

create or replace function public.deactivate_process_party(p_relation_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
begin
  select * into a from public.require_active_actor();
  if a.actor_role not in ('lawyer', 'operator') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  update public.process_party set status = 'inactive', updated_at = now()
  where id = p_relation_id and office_id = a.actor_office_id and status = 'active';
  if not found then
    raise exception 'relation not found or inactive' using errcode = 'P0002';
  end if;
  perform public.write_operational_audit('process_party.deactivated', 'process_party', p_relation_id,
    jsonb_build_object('after', jsonb_build_object('status', 'inactive')));
end;
$$;

create or replace function public.preview_process_import(
  p_normalized_rows jsonb,
  p_content_hash text,
  p_parser_version text,
  p_summary jsonb default '{}'::jsonb
)
returns table(preview_id uuid, expires_at timestamptz, summary jsonb)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  new_id uuid;
  expiry timestamptz;
  normalized_hash text := lower(btrim(coalesce(p_content_hash, '')));
  parser_name text := btrim(coalesce(p_parser_version, ''));
  summary_data jsonb := coalesce(p_summary, '{}'::jsonb);
begin
  select * into a from public.require_active_actor();
  if a.actor_role not in ('lawyer', 'operator') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  if normalized_hash !~ '^[0-9a-f]{64}$' or parser_name = '' or length(parser_name) > 80 or jsonb_typeof(summary_data) <> 'object' then
    raise exception 'invalid import preview metadata' using errcode = '22023';
  end if;
  perform public.phase6_validate_import_rows(p_normalized_rows, a.actor_office_id);
  insert into public.process_import_preview(office_id, created_by, content_hash, parser_version, normalized_rows, summary, expires_at)
  values (a.actor_office_id, a.actor_id, normalized_hash, parser_name, p_normalized_rows, summary_data, now() + interval '30 minutes')
  returning id, process_import_preview.expires_at into new_id, expiry;
  return query select new_id, expiry, summary_data;
end;
$$;

create or replace function public.confirm_process_import(p_preview_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  a record;
  preview public.process_import_preview%rowtype;
  row_data jsonb;
  process_id uuid;
  relation_id uuid;
  client_uuid uuid;
  party_uuid uuid;
  normalized_cnj text;
  role_name text;
  relation_count integer := 0;
  process_count integer := 0;
  result_summary jsonb;
begin
  select * into a from public.require_active_actor();
  if a.actor_role not in ('lawyer', 'operator') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select * into preview from public.process_import_preview where id = p_preview_id for update;
  if preview.id is null or preview.office_id <> a.actor_office_id or preview.created_by <> a.actor_id then
    raise exception 'preview not found' using errcode = 'P0002';
  end if;
  if preview.status = 'consumed' then
    return coalesce(preview.consumed_summary, preview.summary || jsonb_build_object('status', 'consumed'));
  end if;
  if preview.status <> 'pending' or preview.expires_at <= now() then
    if preview.status = 'pending' then
      update public.process_import_preview set status = 'expired' where id = preview.id;
    end if;
    raise exception 'preview expired or unavailable' using errcode = 'P0001';
  end if;

  perform public.phase6_validate_import_rows(preview.normalized_rows, a.actor_office_id);
  for row_data in select value from jsonb_array_elements(preview.normalized_rows) loop
    client_uuid := (row_data ->> 'client_id')::uuid;
    normalized_cnj := public.normalize_cnj(row_data ->> 'cnj_number');
    insert into public.legal_process(office_id, client_id, cnj_number, tribunal, system, is_public, monitoring_status, status, created_by)
    values (a.actor_office_id, client_uuid, normalized_cnj, btrim(row_data ->> 'tribunal'), nullif(btrim(row_data ->> 'system'), ''), coalesce((row_data ->> 'is_public')::boolean, true), 'paused', 'active', a.actor_id)
    returning id into process_id;
    process_count := process_count + 1;
    perform public.write_operational_audit('process.created', 'legal_process', process_id,
      jsonb_build_object('after', jsonb_build_object('cnj_number', normalized_cnj, 'client_id', client_uuid, 'source', 'csv', 'monitoring_status', 'paused', 'status', 'active')));

    if nullif(row_data ->> 'party_id', '') is not null then
      party_uuid := (row_data ->> 'party_id')::uuid;
      role_name := btrim(row_data ->> 'role_in_process');
      insert into public.process_party(office_id, process_id, party_id, role_in_process, source, confirmation_status, confirmed_by, confirmed_at, notes, status, created_by)
      values (a.actor_office_id, process_id, party_uuid, role_name, 'csv', 'pending', null, null, nullif(row_data ->> 'notes', ''), 'active', a.actor_id)
      returning id into relation_id;
      relation_count := relation_count + 1;
      perform public.write_operational_audit('process_party.created', 'process_party', relation_id,
        jsonb_build_object('after', jsonb_build_object('process_id', process_id, 'party_id', party_uuid, 'role_in_process', role_name, 'source', 'csv', 'confirmation_status', 'pending', 'status', 'active')));
    end if;
  end loop;

  result_summary := jsonb_build_object('status', 'consumed', 'preview_id', preview.id, 'processes_created', process_count, 'relations_created', relation_count);
  perform public.write_operational_audit('process.imported', 'process_import_preview', preview.id, result_summary);
  update public.process_import_preview set status = 'consumed', consumed_at = now(), consumed_summary = result_summary where id = preview.id;
  return result_summary;
end;
$$;

alter table public.legal_process enable row level security;
alter table public.process_party enable row level security;
alter table public.process_import_preview enable row level security;

revoke all on public.legal_process, public.process_party, public.process_import_preview from public, anon, authenticated, service_role;
grant select on public.legal_process, public.process_party to authenticated;

create policy legal_process_select_same_office on public.legal_process
for select to authenticated
using (office_id = (select office_id from public.user_profile where id = auth.uid() and is_active = true));

create policy process_party_select_same_office on public.process_party
for select to authenticated
using (office_id = (select office_id from public.user_profile where id = auth.uid() and is_active = true));

revoke all on function public.normalize_cnj(text) from public, anon, authenticated;
revoke all on function public.phase6_validate_import_rows(jsonb, uuid) from public, anon, authenticated;
revoke all on function public.write_operational_audit(text, text, uuid, jsonb) from public, anon, authenticated;

grant execute on function public.create_legal_process(uuid, text, text, text, boolean),
  public.update_legal_process(uuid, text, text, text, boolean),
  public.deactivate_legal_process(uuid),
  public.create_process_party(uuid, uuid, text, text, text),
  public.confirm_process_party(uuid),
  public.reject_process_party(uuid),
  public.deactivate_process_party(uuid),
  public.preview_process_import(jsonb, text, text, jsonb),
  public.confirm_process_import(uuid)
to authenticated;
