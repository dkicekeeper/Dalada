-- Уведомления к функциям сборки 135 (план: docs/02-plan/05-cross-cutting.md, «Уведомления», 1.1;
-- спецификация — docs/04-beta/M24-pushes.md):
--
-- * live_share — друг начал показывать мне, где он (выбрал меня в «Показывать друзьям, где я»).
--   От одного друга — не чаще раза в 6 часов. Настройка notify_live_share.
-- * packing_invite — меня позвали в общие сборы. Настройка notify_trip_tags («Отметки в поездках и
--   общие сборы»): и то и другое — приглашение от друга.
-- * steward — я стал смотрителем места. Одно уведомление, пока статус не перешёл к другому и не
--   вернулся. Настройка notify_steward.
--
-- Общие правила — в push_enqueue: себе нет, между заблокированными нет, без телефона нет, тихие часы.

alter table public.profiles
  add column notify_live_share boolean not null default true,
  add column notify_steward boolean not null default true;
grant update (notify_live_share, notify_steward) on table public.profiles to authenticated;

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
      when 'live_share' then p.notify_live_share
      when 'packing_invite' then p.notify_trip_tags
      when 'steward' then p.notify_steward
      else true
    end
      from public.profiles p
     where p.id = p_user
  ), false);
$$;

-- Трансляция: зритель добавлен при «Показывать друзьям, где я».
create function private.live_share_viewers_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from private.push_outbox o
     where o.user_id = new.viewer_id
       and o.kind = 'live_share'
       and o.payload ->> 'sharer_id' = new.owner_id::text
       and o.created_at > now() - interval '6 hours'
  ) then
    return null;
  end if;
  perform private.push_enqueue(
    new.viewer_id, new.owner_id, 'live_share', jsonb_build_object('sharer_id', new.owner_id)
  );
  return null;
end;
$$;

revoke execute on function private.live_share_viewers_push() from public, anon, authenticated;

create trigger live_share_viewers_push after insert on public.live_share_viewers
  for each row execute function private.live_share_viewers_push();

-- Общие сборы: участник добавлен автором.
create function private.shared_packing_members_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  packing public.shared_packings;
begin
  select * into packing from public.shared_packings where id = new.packing_id;
  if packing.id is null then
    return null;
  end if;
  perform private.push_enqueue(
    new.user_id, packing.owner_id, 'packing_invite',
    jsonb_build_object('packing_id', packing.id, 'title', packing.title)
  );
  return null;
end;
$$;

revoke execute on function private.shared_packing_members_push() from public, anon, authenticated;

create trigger shared_packing_members_push after insert on public.shared_packing_members
  for each row execute function private.shared_packing_members_push();

-- Смотритель: кому уже сообщили по каждому месту (чтобы не повторять после каждого отчёта).
create table private.place_steward_notified (
  place_id    uuid primary key references public.places (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  notified_at timestamptz not null default now()
);

alter table private.place_steward_notified enable row level security;

-- Новый или изменённый подтверждённый публичный отчёт: автор стал смотрителем — уведомить один раз.
create function private.checkins_steward_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  steward uuid;
  notified uuid;
begin
  if not (new.verified and new.visibility = 'public' and new.deleted_at is null) then
    return null;
  end if;
  if not private.is_open_place(new.place_id, null) then
    return null;
  end if;
  select s.user_id into steward from private.place_steward_id(new.place_id) s;
  if steward is distinct from new.owner_id then
    return null;
  end if;
  select n.user_id into notified from private.place_steward_notified n where n.place_id = new.place_id;
  if notified = new.owner_id then
    return null;
  end if;

  insert into private.place_steward_notified (place_id, user_id)
  values (new.place_id, new.owner_id)
  on conflict (place_id) do update set user_id = excluded.user_id, notified_at = now();

  perform private.push_enqueue(
    new.owner_id, null, 'steward',
    jsonb_build_object(
      'place_id', new.place_id,
      'place_name', (select p.name from public.places p where p.id = new.place_id)
    )
  );
  return null;
end;
$$;

revoke execute on function private.checkins_steward_push() from public, anon, authenticated;

create trigger checkins_steward_push after insert or update of verified, visibility on public.checkins
  for each row execute function private.checkins_steward_push();
