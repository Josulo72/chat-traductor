-- Chat Traductor v2: conversaciones privadas ES <-> PT-BR
-- IMPORTANTE: establecer owner_id con el UUID de la sesión española existente.
-- Esta migración crea tablas nuevas; no borra conversaciones antiguas.
create extension if not exists pgcrypto;

create table if not exists public.chat_v2_config (
  singleton boolean primary key default true check (singleton),
  owner_id uuid references auth.users(id),
  bootstrap_hash text,
  check ((owner_id is null and bootstrap_hash is not null) or (owner_id is not null and bootstrap_hash is null))
);

create table if not exists public.chat_v2_rooms (
  id uuid primary key default gen_random_uuid(),
  guest_id uuid not null unique references auth.users(id),
  guest_name text not null check (char_length(trim(guest_name)) between 1 and 40),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_v2_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_v2_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  source_lang text not null check (source_lang in ('es', 'pt-BR')),
  source_text text not null check (char_length(trim(source_text)) between 1 and 5000),
  translated_text text,
  status text not null default 'pending' check (status in ('pending', 'translated', 'failed')),
  created_at timestamptz not null default now()
);
create index if not exists chat_v2_messages_room_date_idx on public.chat_v2_messages(room_id, created_at desc);

alter table public.chat_v2_config enable row level security;
alter table public.chat_v2_rooms enable row level security;
alter table public.chat_v2_messages enable row level security;

revoke all on public.chat_v2_config from anon, authenticated;
revoke all on public.chat_v2_rooms from anon, authenticated;
revoke all on public.chat_v2_messages from anon, authenticated;
grant select on public.chat_v2_config to authenticated;
grant select, update on public.chat_v2_rooms to authenticated;
grant select, insert on public.chat_v2_messages to authenticated;

create policy "v2 config only owner" on public.chat_v2_config for select to authenticated
using (owner_id = (select auth.uid()));

create policy "v2 rooms only participants" on public.chat_v2_rooms for select to authenticated
using (guest_id = (select auth.uid()) and active or exists (
  select 1 from public.chat_v2_config c where c.owner_id = (select auth.uid())
));
create policy "v2 rooms admin may close" on public.chat_v2_rooms for update to authenticated
using (exists (select 1 from public.chat_v2_config c where c.owner_id = (select auth.uid())))
with check (exists (select 1 from public.chat_v2_config c where c.owner_id = (select auth.uid())));

create policy "v2 messages only participants" on public.chat_v2_messages for select to authenticated
using (exists (
  select 1 from public.chat_v2_rooms r where r.id = room_id
  and (r.active and r.guest_id = (select auth.uid())
    or exists (select 1 from public.chat_v2_config c where c.owner_id = (select auth.uid())))
));
create policy "v2 insert only sender participant" on public.chat_v2_messages for insert to authenticated
with check (
  sender_id = (select auth.uid()) and
  status = 'pending' and translated_text is null and
  exists (
    select 1 from public.chat_v2_rooms r
    where r.id = room_id and r.active
    and (
      (r.guest_id = (select auth.uid()) and source_lang = 'pt-BR') or
      (source_lang = 'es' and exists (
        select 1 from public.chat_v2_config c where c.owner_id = (select auth.uid())
      ))
    )
  )
);

create or replace function public.chat_v2_register(p_name text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room uuid;
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if p_name is null or char_length(trim(p_name)) not between 1 and 40
  then raise exception 'invalid_name'; end if;
  if exists (select 1 from public.chat_v2_config c where c.owner_id = v_uid)
  then raise exception 'admin_cannot_register'; end if;
  if exists (select 1 from public.profiles p where p.id = v_uid and p.lang = 'bg')
  then raise exception 'legacy_access_revoked'; end if;
  insert into public.chat_v2_rooms (guest_id, guest_name)
  values (v_uid, trim(p_name))
  on conflict (guest_id) do nothing;
  select id into v_room from public.chat_v2_rooms
  where guest_id = v_uid and active = true;
  if v_room is null then raise exception 'access_revoked'; end if;
  return v_room;
end
$$;
revoke all on function public.chat_v2_register(text) from public, anon;
grant execute on function public.chat_v2_register(text) to authenticated;

-- La clave inicial de administración se introduce por SQL privado, nunca en GitHub.
-- insert into public.chat_v2_config(singleton,bootstrap_hash)
-- values (true, extensions.crypt('<SECRETO_PRIVADO>',extensions.gen_salt('bf',12)));

create or replace function public.chat_v2_claim_admin(p_secret text)
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_updated integer;
begin
  if v_uid is null or p_secret is null or char_length(p_secret) > 200
  then return false; end if;
  update public.chat_v2_config c
  set owner_id = v_uid, bootstrap_hash = null
  where c.singleton and c.owner_id is null
    and c.bootstrap_hash = extensions.crypt(p_secret, c.bootstrap_hash);
  get diagnostics v_updated = row_count;
  return v_updated = 1;
end
$$;
revoke all on function public.chat_v2_claim_admin(text) from public, anon;
grant execute on function public.chat_v2_claim_admin(text) to authenticated;

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='chat_v2_messages')
  then alter publication supabase_realtime add table public.chat_v2_messages; end if;
end $$;
