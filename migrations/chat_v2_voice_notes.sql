-- Voice notes in private conversations; same scoped bucket as photos/videos.
update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif','video/mp4','video/quicktime','video/webm','audio/mp4','audio/webm','audio/ogg','audio/aac','audio/mpeg']
where id='chat-v2-media';

alter table public.chat_v2_messages drop constraint if exists chat_v2_media_kind_check;
alter table public.chat_v2_messages add constraint chat_v2_media_kind_check
check ((media_kind is null and media_path is null and media_mime is null)
 or (media_kind in ('image','video','audio') and media_path is not null and media_mime is not null));

create or replace function public.chat_v2_media_allowed(p_name text)
returns boolean language sql stable security definer set search_path=''
as $$
 select auth.uid() is not null
 and exists (
   select 1 from public.chat_v2_rooms r where r.id::text=split_part(p_name,'/',1)
   and r.active and (r.guest_id=auth.uid() or exists (
     select 1 from public.chat_v2_config c where c.owner_id=auth.uid()
   ))
 )
 and split_part(p_name,'/',2)=auth.uid()::text
 and p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|jpeg|png|webp|gif|heic|heif|mp4|mov|webm|ogg|aac|mp3)$';
$$;

drop policy if exists "v2 insert only sender participant" on public.chat_v2_messages;
create policy "v2 insert only sender participant" on public.chat_v2_messages for insert to authenticated
with check (
  sender_id=(select auth.uid()) and status='pending' and translated_text is null
  and (
    (media_kind is null and media_path is null and media_mime is null)
    or (media_kind in ('image','video','audio') and media_path like (room_id::text||'/'||sender_id::text||'/%')
      and ((media_kind='image' and media_mime in ('image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif'))
      or (media_kind='video' and media_mime in ('video/mp4','video/quicktime','video/webm'))
      or (media_kind='audio' and media_mime in ('audio/mp4','audio/webm','audio/ogg','audio/aac','audio/mpeg'))))
  )
  and exists (select 1 from public.chat_v2_rooms r
    where r.id=room_id and r.active and r.guest_id is not null
      and ((r.guest_id=(select auth.uid()) and source_lang='pt-BR')
       or (source_lang='es' and exists
        (select 1 from public.chat_v2_config c where c.owner_id=(select auth.uid())))))
);
