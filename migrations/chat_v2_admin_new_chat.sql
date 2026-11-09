-- V2 admin-created rooms. Pending rooms are visible ONLY to admin.
alter table public.chat_v2_rooms alter column guest_id drop not null;

create unique index if not exists chat_v2_pending_guest_name_uq
on public.chat_v2_rooms (lower(btrim(guest_name)))
where guest_id is null;

create or replace function public.chat_v2_create_room(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text := btrim(p_name);
begin
  if v_uid is null or
     not exists(select 1 from public.chat_v2_config c where c.owner_id=v_uid)
  then raise exception 'not_admin' using errcode='42501'; end if;
  if v_name is null or char_length(v_name) not between 1 and 40
  then raise exception 'invalid_name'; end if;
  insert into public.chat_v2_rooms (guest_name)
  values (v_name)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'name_already_waiting';
end
$$;
revoke all on function public.chat_v2_create_room(text) from public, anon;
grant execute on function public.chat_v2_create_room(text) to authenticated;

create or replace function public.chat_v2_register(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room uuid;
  v_name text := btrim(p_name);
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if v_name is null or char_length(v_name) not between 1 and 40
  then raise exception 'invalid_name'; end if;
  if exists(select 1 from public.chat_v2_config c where c.owner_id=v_uid)
  then raise exception 'admin_cannot_register'; end if;
  if exists(select 1 from public.profiles p where p.id=v_uid and p.lang='bg')
  then raise exception 'legacy_access_revoked'; end if;

  -- Return an existing personal room when the same browser returns.
  select id into v_room from public.chat_v2_rooms
  where guest_id=v_uid;
  if v_room is not null then
    if not exists(select 1 from public.chat_v2_rooms where id=v_room and active)
    then raise exception 'access_revoked'; end if;
    return v_room;
  end if;

  -- Name matching attaches to a pending conversation prepared by the owner.
  -- A name is NOT an identity proof: do not send sensitive messages before confirmation.
  update public.chat_v2_rooms r set guest_id=v_uid
  where r.id=(
    select q.id from public.chat_v2_rooms q
    where q.guest_id is null and q.active
      and lower(btrim(q.guest_name))=lower(v_name)
    order by q.created_at
    limit 1
    for update skip locked
  )
  returning r.id into v_room;

  if v_room is not null then return v_room; end if;

  insert into public.chat_v2_rooms (guest_id, guest_name)
  values (v_uid,v_name)
  returning id into v_room;
  return v_room;
end
$$;
revoke all on function public.chat_v2_register(text) from public, anon;
grant execute on function public.chat_v2_register(text) to authenticated;
