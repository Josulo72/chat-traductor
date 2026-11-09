-- Llamadas 1:1, señalización privada. Nunca almacena audio ni vídeo.
create table if not exists public.chat_v2_calls(
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.chat_v2_rooms(id) on delete cascade,
 caller_id uuid not null references auth.users(id),
 kind text not null check (kind in ('audio','video')),
 status text not null default 'ringing' check (status in ('ringing','active','declined','ended')),
 offer jsonb not null,
 answer jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists chat_v2_one_live_call on public.chat_v2_calls(room_id) where status in ('ringing','active');
create index if not exists chat_v2_calls_room_created on public.chat_v2_calls(room_id,created_at desc);
create table if not exists public.chat_v2_ice_candidates(
 id bigint generated always as identity primary key,
 call_id uuid not null references public.chat_v2_calls(id) on delete cascade,
 sender_id uuid not null references auth.users(id),
 candidate jsonb not null,
 created_at timestamptz not null default now()
);
create index if not exists chat_v2_ice_call_id on public.chat_v2_ice_candidates(call_id,id);

alter table public.chat_v2_calls enable row level security;
alter table public.chat_v2_ice_candidates enable row level security;
revoke all on public.chat_v2_calls from anon, authenticated;
revoke all on public.chat_v2_ice_candidates from anon, authenticated;
grant select on public.chat_v2_calls to authenticated;
grant select,insert on public.chat_v2_ice_candidates to authenticated;

create or replace function public.chat_v2_is_participant(p_room uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select auth.uid() is not null and exists (
 select 1 from public.chat_v2_rooms r
 where r.id=p_room and r.active and r.guest_id is not null
 and (r.guest_id=auth.uid() or exists (
   select 1 from public.chat_v2_config c where c.owner_id=auth.uid()
 ))) $$;
revoke all on function public.chat_v2_is_participant(uuid) from public,anon;
grant execute on function public.chat_v2_is_participant(uuid) to authenticated;

create policy chat_v2_calls_select on public.chat_v2_calls
for select to authenticated using (public.chat_v2_is_participant(room_id));
create policy chat_v2_ice_select on public.chat_v2_ice_candidates
for select to authenticated using (
 exists (select 1 from public.chat_v2_calls c
 where c.id=call_id and public.chat_v2_is_participant(c.room_id)));
create policy chat_v2_ice_insert on public.chat_v2_ice_candidates
for insert to authenticated with check (
 sender_id=auth.uid()
 and jsonb_typeof(candidate)='object'
 and pg_catalog.octet_length(candidate::text) < 5000
 and exists (select 1 from public.chat_v2_calls c where c.id=call_id
  and c.status in ('ringing','active')
  and public.chat_v2_is_participant(c.room_id))
);

create or replace function public.chat_v2_start_call(p_room uuid,p_kind text,p_offer jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if not public.chat_v2_is_participant(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_kind not in ('audio','video') or jsonb_typeof(p_offer)<>'object'
   or pg_catalog.octet_length(p_offer::text)>150000 then raise exception 'invalid_offer'; end if;
 -- Expire stale ringing calls so they never permanently lock a room.
 update public.chat_v2_calls set status='ended',updated_at=now()
 where room_id=p_room and status='ringing' and created_at < now()-interval '90 seconds';
 insert into public.chat_v2_calls(room_id,caller_id,kind,offer)
 values(p_room,auth.uid(),p_kind,p_offer) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.chat_v2_start_call(uuid,text,jsonb) from public,anon;
grant execute on function public.chat_v2_start_call(uuid,text,jsonb) to authenticated;

create or replace function public.chat_v2_answer_call(p_call uuid,p_answer jsonb)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_count integer;
begin
 if jsonb_typeof(p_answer)<>'object' or pg_catalog.octet_length(p_answer::text)>150000
 then raise exception 'invalid_answer'; end if;
 update public.chat_v2_calls c set answer=p_answer,status='active',updated_at=now()
 where c.id=p_call and c.status='ringing'
 and c.caller_id<>auth.uid()
 and c.created_at > now()-interval '90 seconds'
 and public.chat_v2_is_participant(c.room_id);
 get diagnostics v_count=row_count;
 return v_count=1;
end $$;
revoke all on function public.chat_v2_answer_call(uuid,jsonb) from public,anon;
grant execute on function public.chat_v2_answer_call(uuid,jsonb) to authenticated;

create or replace function public.chat_v2_finish_call(p_call uuid,p_decline boolean default false)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_count integer;
begin
 update public.chat_v2_calls c
 set status=case when p_decline and status='ringing' then 'declined' else 'ended' end,
 updated_at=now()
 where c.id=p_call and c.status in ('ringing','active')
 and public.chat_v2_is_participant(c.room_id);
 get diagnostics v_count=row_count;
 return v_count=1;
end $$;
revoke all on function public.chat_v2_finish_call(uuid,boolean) from public,anon;
grant execute on function public.chat_v2_finish_call(uuid,boolean) to authenticated;