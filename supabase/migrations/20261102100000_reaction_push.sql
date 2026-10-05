-- Уведомление о реакции (план: docs/02-plan/05-notifications.md — «Реакция или комментарий к моей
-- поездке или улову»): «респект» поездке, отчёту или ответу в обсуждении и «полезно» отзыву.
--
-- Автору — не чаще одного уведомления от одного человека об одной записи в сутки (поставил, снял,
-- поставил снова — одно). Себе — нет; между заблокированными, без телефона и при выключенной
-- настройке — нет (push_enqueue, push_allowed). Отключается в настройках: notify_reactions.

alter table public.profiles add column notify_reactions boolean not null default true;
grant update (notify_reactions) on table public.profiles to authenticated;

create or replace function private.push_allowed(p_user uuid, p_kind public.push_kind) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case p_kind
      when 'thread_reply' then p.notify_replies
      when 'friend_request' then p.notify_friend_requests
      when 'friend_accept' then p.notify_friend_requests
      when 'comment' then p.notify_comments
      when 'friend_post' then p.notify_friend_posts
      when 'ban_start' then p.notify_bans
      when 'ban_end' then p.notify_bans
      when 'place_activity' then p.notify_place_activity
      when 'trip_tag' then p.notify_trip_tags
      when 'reaction' then p.notify_reactions
      else true
    end
      from public.profiles p
     where p.id = p_user
  ), false);
$$;

-- Что за запись и куда вести по нажатию: поездка — её название; отчёт и отзыв — место;
-- ответ в обсуждении — обсуждение.
create function private.reactions_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient uuid := private.reaction_target_owner(new.target_kind, new.target_id);
  payload jsonb;
begin
  if recipient is null or recipient = new.owner_id then
    return null;
  end if;
  if exists (
    select 1 from private.push_outbox o
     where o.user_id = recipient
       and o.kind = 'reaction'
       and o.payload ->> 'target_id' = new.target_id::text
       and o.payload ->> 'actor_id' = new.owner_id::text
       and o.created_at > now() - interval '1 day'
  ) then
    return null;
  end if;

  payload := jsonb_build_object(
    'target_kind', new.target_kind,
    'target_id', new.target_id,
    'actor_id', new.owner_id
  );
  payload := payload || case new.target_kind
    when 'trip' then (
      select jsonb_build_object('title', t.title) from public.trips t where t.id = new.target_id)
    when 'checkin' then (
      select jsonb_build_object('title', p.name, 'place_id', p.id)
        from public.checkins c join public.places p on p.id = c.place_id where c.id = new.target_id)
    when 'review' then (
      select jsonb_build_object('title', p.name, 'place_id', p.id)
        from public.reviews r join public.places p on p.id = r.place_id where r.id = new.target_id)
    when 'post' then (
      select jsonb_build_object('title', th.title, 'thread_id', th.id)
        from public.thread_posts tp join public.threads th on th.id = tp.thread_id where tp.id = new.target_id)
  end;

  perform private.push_enqueue(recipient, new.owner_id, 'reaction', coalesce(payload, '{}'::jsonb));
  return null;
end;
$$;

revoke execute on function private.reactions_push() from public, anon, authenticated;

create trigger reactions_push after insert on public.reactions
  for each row execute function private.reactions_push();
