create or replace function public.get_process_import_preview(p_preview_id uuid)
returns table(
  preview_id uuid,
  content_hash text,
  parser_version text,
  normalized_rows jsonb,
  summary jsonb,
  expires_at timestamptz,
  status text,
  consumed_at timestamptz,
  consumed_summary jsonb
)
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
  return query
  select p.id, p.content_hash, p.parser_version, p.normalized_rows, p.summary, p.expires_at, p.status, p.consumed_at, p.consumed_summary
  from public.process_import_preview p
  where p.id = p_preview_id
    and p.office_id = a.actor_office_id
    and p.created_by = a.actor_id;
end;
$$;

revoke all on function public.get_process_import_preview(uuid) from public, anon, authenticated;
grant execute on function public.get_process_import_preview(uuid) to authenticated;
