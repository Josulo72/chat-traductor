-- Fotos y vídeos privados, sin acceso entre conversaciones.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('chat-v2-media','chat-v2-media',false,26214400,
array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif','video/mp4','video/quicktime','video/webm'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

alter table public.chat_v2_messages
 add column if not exists media_kind text,
 add column if not exists media_path text,
 add column if not exists media_mime text;

alter table public.chat_v2_messages
 add constraint chat_v2_media_kind_check
 check ((media_kind is null and media_path is null and media_mime is null)
 or (media_kind in ('image','video') and media_path is not null and media_mime is not null));

create or replace function public.chat_v2_media_allowed(p_name text)
returns boolean language sql stable security definer
set search_path=''
as $$
 select
  auth.uid() is not null
  and exists (
    select 1 from public.chat_v2_rooms r
    where r.id::text = split_part(p_name,'/',1) and r.active
    and (r.guest_id=auth.uid() or exists (
       select 1 from public.chat_v2_config c where c.owner_id=auth.uid()
    ))
  )
  and split_part(p_name,'/',2) = auth.uid()::text
  and p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|gif|heic|heif|mp4|mov|webm);
$$;
revoke all on function public.chat_v2_media_allowed(text) from public, anon;
grant execute on function public.chat_v2_media_allowed(text) to authenticated;

create or replace function public.chat_v2_media_can_read(p_name text)
returns boolean language sql stable security definer
set search_path=''
as $$
 select auth.uid() is not null and exists (
  select 1 from public.chat_v2_rooms r
  where r.id::text = split_part(p_name,'/',1)
  and (
    (r.active and r.guest_id=auth.uid())
    or exists (select 1 from public.chat_v2_config c where c.owner_id=auth.uid())
  )
 );
$$;
revoke all on function public.chat_v2_media_can_read(text) from public, anon;
grant execute on function public.chat_v2_media_can_read(text) to authenticated;

create policy chat_v2_media_select on storage.objects
for select to authenticated
using (bucket_id='chat-v2-media' and public.chat_v2_media_can_read(name));

create policy chat_v2_media_insert on storage.objects
for insert to authenticated
with check (bucket_id='chat-v2-media' and owner=auth.uid()
 and public.chat_v2_media_allowed(name));

create policy chat_v2_media_delete_orphan on storage.objects
for delete to authenticated
using (bucket_id='chat-v2-media' and owner=auth.uid() and public.chat_v2_media_allowed(name));

drop policy if exists "v2 insert only sender participant" on public.chat_v2_messages;
create policy "v2 insert only sender participant" on public.chat_v2_messages for insert to authenticated
with check (
  sender_id=(select auth.uid())
  and status='pending' and translated_text is null
  and (
    (media_kind is null and media_path is null and media_mime is null)
    or (media_kind in ('image','video') and media_path like (room_id::text||'/'||sender_id::text||'/%')
      and ((media_kind='image' and media_mime in ('image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif'))
      or (media_kind='video' and media_mime in ('video/mp4','video/quicktime','video/webm'))))
  )
  and exists (select 1 from public.chat_v2_rooms r
    where r.id=room_id and r.active and r.guest_id is not null
      and ((r.guest_id=(select auth.uid()) and source_lang='pt-BR')
       or (source_lang='es' and exists
        (select 1 from public.chat_v2_config c where c.owner_id=(select auth.uid())))))
);
;
$$;
revoke all on function public.chat_v2_media_allowed(text) from public, anon;
grant execute on function public.chat_v2_media_allowed(text) to authenticated;

create or replace function public.chat_v2_media_can_read(p_name text)
returns boolean language sql stable security definer
set search_path=''
as $$
 select auth.uid() is not null and exists (
  select 1 from public.chat_v2_rooms r
  where r.id::text = split_part(p_name,'/',1)
  and (
    (r.active and r.guest_id=auth.uid())
    or exists (select 1 from public.chat_v2_config c where c.owner_id=auth.uid())
  )
 );
$$;
revoke all on function public.chat_v2_media_can_read(text) from public, anon;
grant execute on function public.chat_v2_media_can_read(text) to authenticated;

create policy chat_v2_media_select on storage.objects
for select to authenticated
using (bucket_id='chat-v2-media' and public.chat_v2_media_can_read(name));

create policy chat_v2_media_insert on storage.objects
for insert to authenticated
with check (bucket_id='chat-v2-media' and owner=auth.uid()
 and public.chat_v2_media_allowed(name));

create policy chat_v2_media_delete_orphan on storage.objects
for delete to authenticated
using (bucket_id='chat-v2-media' and owner=auth.uid() and public.chat_v2_media_allowed(name));

drop policy if exists "v2 insert only sender participant" on public.chat_v2_messages;
create policy "v2 insert only sender participant" on public.chat_v2_messages for insert to authenticated
with check (
  sender_id=(select auth.uid())
  and status='pending' and translated_text is null
  and (
    (media_kind is null and media_path is null and media_mime is null)
    or (media_kind in ('image','video') and media_path like (room_id::text||'/'||sender_id::text||'/%')
      and ((media_kind='image' and media_mime in ('image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif'))
      or (media_kind='video' and media_mime in ('video/mp4','video/quicktime','video/webm'))))
  )
  and exists (select 1 from public.chat_v2_rooms r
    where r.id=room_id and r.active and r.guest_id is not null
      and ((r.guest_id=(select auth.uid()) and source_lang='pt-BR')
       or (source_lang='es' and exists
        (select 1 from public.chat_v2_config c where c.owner_id=(select auth.uid())))))
);
