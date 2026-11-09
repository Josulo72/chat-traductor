alter table public.chat_v2_config add column if not exists avatar_path text;
grant update (avatar_path) on public.chat_v2_config to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('chat-v2-avatar','chat-v2-avatar',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.chat_v2_avatar_readable(p_name text)
returns boolean language sql stable security definer set search_path=''
as $$
 select auth.uid() is not null and exists(
  select 1 from public.chat_v2_config c
  where split_part(p_name,'/',1)=c.owner_id::text
  and (auth.uid()=c.owner_id or exists (
    select 1 from public.chat_v2_rooms r where r.guest_id=auth.uid() and r.active
  )));
$$;
revoke all on function public.chat_v2_avatar_readable(text) from public,anon;
grant execute on function public.chat_v2_avatar_readable(text) to authenticated;

create policy chat_v2_avatar_read on storage.objects for select to authenticated
using(bucket_id='chat-v2-avatar' and public.chat_v2_avatar_readable(name));
create policy chat_v2_avatar_upload on storage.objects for insert to authenticated
with check(bucket_id='chat-v2-avatar' and owner=auth.uid()
 and split_part(name,'/',1)=auth.uid()::text
 and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|png|webp)$'
 and exists (select 1 from public.chat_v2_config c where c.owner_id=auth.uid()));

create or replace function public.chat_v2_owner_profile()
returns jsonb language sql stable security definer set search_path=''
as $$
 select case when auth.uid() is not null and (
  exists(select 1 from public.chat_v2_config c where c.owner_id=auth.uid())
  or exists(select 1 from public.chat_v2_rooms r where r.guest_id=auth.uid() and r.active))
 then (select jsonb_build_object('name',c.display_name,'avatar',c.avatar_path)
 from public.chat_v2_config c limit 1) else null end;
$$;
revoke all on function public.chat_v2_owner_profile() from public,anon;
grant execute on function public.chat_v2_owner_profile() to authenticated;