-- M15: участники поездки (автор отмечает друзей) и личные рекорды уловов.
--
-- Участники: автор отмечает друзей (до 20 на поездку), отмеченный принимает или отклоняет. Ждущий
-- ответа и принявший видят поездку независимо от её видимости — трек, как и всем кроме автора, без
-- начала, конца и скрытых участков (private.visible_track). Отклонивший (или вышедший) видит поездку
-- только по видимости, и отметить его в ней снова нельзя: строка остаётся со статусом declined.
-- Таблица клиенту напрямую закрыта — всё через RPC.

-- Участники ------------------------------------------------------------------------------------

create type public.trip_participant_status as enum ('pending', 'accepted', 'declined');

create table public.trip_participants (
  trip_id      uuid not null references public.trips (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  status       public.trip_participant_status not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  primary key (trip_id, user_id)
);

create index trip_participants_user_idx on public.trip_participants (user_id, status);

comment on table public.trip_participants is
  'Отмеченные в поездке друзья. Клиенту напрямую закрыта; RPC tag_trip_friends, respond_trip_tag и др.';

alter table public.trip_participants enable row level security;
revoke all on table public.trip_participants from anon, authenticated;

create function private.trip_participants_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 20 $$;

-- Отмечен в поездке (ждёт ответа или принял) и с автором не заблокирован.
create function private.is_trip_participant(p_trip uuid, p_viewer uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_viewer is not null and exists (
    select 1
      from public.trip_participants tp
      join public.trips t on t.id = tp.trip_id
     where tp.trip_id = p_trip
       and tp.user_id = p_viewer
       and tp.status in ('pending', 'accepted')
       and not private.is_blocked(p_viewer, t.owner_id)
  );
$$;

-- Видит ли зритель поездку: по её видимости или как участник. Удалённую — никто.
create function private.can_view_trip(p_viewer uuid, p_trip public.trips) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_trip.deleted_at is null
     and (private.can_view(p_viewer, p_trip.owner_id, p_trip.visibility)
          or private.is_trip_participant(p_trip.id, p_viewer));
$$;

-- Поездка, реакции и комментарии к ней — и для участников ------------------------------------------

create or replace function private.reaction_target_visible(
  p_viewer uuid,
  p_kind public.reaction_target,
  p_target uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_kind
    when 'trip' then exists (
      select 1 from public.trips t
       where t.id = p_target
         and private.can_view_trip(p_viewer, t))
    when 'checkin' then exists (
      select 1 from public.checkins c
        join public.places p on p.id = c.place_id
       where c.id = p_target
         and c.deleted_at is null
         and p.deleted_at is null
         and (p.status = 'published' or p.owner_id = p_viewer)
         and private.can_view(p_viewer, p.owner_id, p.visibility)
         and private.can_view(p_viewer, c.owner_id, c.visibility))
    when 'review' then exists (
      select 1 from public.reviews r
       where r.id = p_target
         and r.deleted_at is null
         and private.is_open_place(r.place_id, p_viewer)
         and (p_viewer is null or not private.is_blocked(p_viewer, r.owner_id)))
    when 'post' then exists (
      select 1 from public.thread_posts x
        join public.threads t on t.id = x.thread_id
       where x.id = p_target
         and x.deleted_at is null
         and t.deleted_at is null
         and private.is_open_place(t.place_id, p_viewer)
         and (p_viewer is null
              or (not private.is_blocked(p_viewer, x.owner_id)
                  and not private.is_blocked(p_viewer, t.owner_id))))
    else false
  end;
$$;

create or replace function public.trip_view(p_trip uuid)
returns table (
  id uuid,
  owner_id uuid,
  owner_username text,
  owner_display_name text,
  owner_avatar_path text,
  activity public.trip_activity,
  title text,
  note text,
  started_at timestamptz,
  ended_at timestamptz,
  moving_seconds integer,
  distance_m integer,
  elevation_gain_m integer,
  max_speed_mps real,
  visibility public.visibility,
  is_own boolean,
  track jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.owner_id, pr.username, pr.display_name, pr.avatar_path,
         t.activity, t.title, t.note, t.started_at, t.ended_at,
         t.moving_seconds, t.distance_m, t.elevation_gain_m, t.max_speed_mps, t.visibility,
         t.owner_id = auth.uid(),
         extensions.st_asgeojson(private.visible_track(t, auth.uid()), 6)::jsonb
    from public.trips t
    join public.profiles pr on pr.id = t.owner_id
   where t.id = p_trip
     and private.can_view_trip(auth.uid(), t);
$$;

create or replace function public.trip_checkins(p_trip uuid)
returns table (
  checkin_id uuid,
  at timestamptz,
  verified boolean,
  place_id uuid,
  place_name text,
  conditions jsonb,
  note text,
  catches jsonb,
  media jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.at, c.verified,
         case when pv.visible then p.id end,
         case when pv.visible then p.name end,
         c.conditions, c.note,
         private.checkin_catches_json(c.id, auth.uid()),
         private.checkin_media_json(c.id, auth.uid())
    from public.trips t
    join public.checkins c
      on c.owner_id = t.owner_id
     and c.at between t.started_at and t.ended_at
     and c.deleted_at is null
    join public.places p on p.id = c.place_id
    cross join lateral (
      select p.deleted_at is null
             and (p.status = 'published' or p.owner_id = auth.uid())
             and private.can_view(auth.uid(), p.owner_id, p.visibility) as visible
    ) pv
   where t.id = p_trip
     and private.can_view_trip(auth.uid(), t)
     and private.can_view(auth.uid(), c.owner_id, c.visibility)
   order by c.at;
$$;

-- RPC: отметки ----------------------------------------------------------------------------------

-- Отметить друзей в своей поездке. Не друзья и заблокированные пропускаются молча (отметки с финиша
-- уходят из очереди отправки, когда дружба могла уже кончиться); кто уже отмечен, в том числе
-- отклонил, — без изменений. Новым отмеченным — уведомление (одно на человека и поездку).
-- Возвращает, сколько человек отмечено сейчас.
create function public.tag_trip_friends(p_trip uuid, p_users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  t public.trips;
  u uuid;
  added integer := 0;
  inserted boolean;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  select * into t from public.trips where id = p_trip and owner_id = me and deleted_at is null;
  if not found then
    raise exception 'trip not found' using errcode = 'P0002';
  end if;

  for u in
    select distinct x.id from unnest(coalesce(p_users, '{}'::uuid[])) as x(id)
     where x.id is not null and x.id <> me
  loop
    if not private.are_friends(me, u) or private.is_blocked(me, u) then
      continue;
    end if;
    if (select count(*) from public.trip_participants tp
         where tp.trip_id = p_trip and tp.status in ('pending', 'accepted')) >= private.trip_participants_limit() then
      raise exception 'too many participants' using errcode = '54000';
    end if;

    insert into public.trip_participants (trip_id, user_id)
    values (p_trip, u)
    on conflict (trip_id, user_id) do nothing
    returning true into inserted;

    if inserted then
      added := added + 1;
      if not exists (
        select 1 from private.push_outbox o
         where o.user_id = u
           and o.kind = 'trip_tag'
           and o.payload ->> 'target_id' = p_trip::text
      ) then
        perform private.push_enqueue(
          u, me, 'trip_tag',
          jsonb_build_object('target_kind', 'trip', 'target_id', p_trip, 'title', t.title)
        );
      end if;
    end if;
    inserted := null;
  end loop;

  return added;
end;
$$;

-- Убрать отметку со своей поездки (ждёт ответа или принял). Отклонившего автор не видит и не убирает.
create function public.untag_trip_friend(p_trip uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  delete from public.trip_participants tp
   using public.trips t
   where tp.trip_id = p_trip
     and tp.user_id = p_user
     and tp.status in ('pending', 'accepted')
     and t.id = tp.trip_id
     and t.owner_id = auth.uid();
end;
$$;

-- Ответ отмеченного: принять или отклонить; «выйти из поездки» — отклонить после принятия.
create function public.respond_trip_tag(p_trip uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  update public.trip_participants tp
     set status = case when p_accept then 'accepted' else 'declined' end::public.trip_participant_status,
         responded_at = now()
    from public.trips t
   where tp.trip_id = p_trip
     and tp.user_id = me
     and t.id = tp.trip_id
     and t.deleted_at is null
     and not private.is_blocked(me, t.owner_id)
     and (tp.status = 'pending' or (tp.status = 'accepted' and not p_accept));
  if not found then
    raise exception 'invitation not found' using errcode = 'P0002';
  end if;
end;
$$;

-- Участники поездки, которых видит зритель: автору — ждущие ответа и принявшие, остальным — принявшие
-- и он сам, если отмечен. Только если зритель видит поездку; заблокированные зрителем — не видны.
create function public.trip_participants(p_trip uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_path text,
  status public.trip_participant_status,
  is_me boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select pr.id, pr.username, pr.display_name, pr.avatar_path, tp.status, tp.user_id = auth.uid()
    from public.trips t
    join public.trip_participants tp on tp.trip_id = t.id
    join public.profiles pr on pr.id = tp.user_id
   where t.id = p_trip
     and private.can_view_trip(auth.uid(), t)
     and (tp.status = 'accepted'
          or (tp.status = 'pending' and (t.owner_id = auth.uid() or tp.user_id = auth.uid())))
     and not private.is_blocked(auth.uid(), tp.user_id)
   order by tp.status = 'pending', coalesce(pr.display_name, pr.username);
$$;

-- Приглашения: поездки, где меня отметили и я ещё не ответил. Новые сверху.
create function public.my_trip_invitations()
returns table (
  trip_id uuid,
  title text,
  activity public.trip_activity,
  started_at timestamptz,
  ended_at timestamptz,
  owner_id uuid,
  owner_username text,
  owner_display_name text,
  owner_avatar_path text,
  tagged_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.title, t.activity, t.started_at, t.ended_at,
         pr.id, pr.username, pr.display_name, pr.avatar_path, tp.created_at
    from public.trip_participants tp
    join public.trips t on t.id = tp.trip_id
    join public.profiles pr on pr.id = t.owner_id
   where tp.user_id = auth.uid()
     and tp.status = 'pending'
     and t.deleted_at is null
     and not private.is_blocked(auth.uid(), t.owner_id)
   order by tp.created_at desc
   limit 20;
$$;

-- Чужие поездки, в которых я участник (принял), без трека — для «Моих поездок».
create function public.my_joined_trips(p_limit integer default 50)
returns table (
  id uuid,
  activity public.trip_activity,
  title text,
  note text,
  started_at timestamptz,
  ended_at timestamptz,
  moving_seconds integer,
  distance_m integer,
  elevation_gain_m integer,
  max_speed_mps real,
  visibility public.visibility,
  host_id uuid,
  host_username text,
  host_display_name text,
  host_avatar_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.activity, t.title, t.note, t.started_at, t.ended_at,
         t.moving_seconds, t.distance_m, t.elevation_gain_m, t.max_speed_mps, t.visibility,
         pr.id, pr.username, pr.display_name, pr.avatar_path
    from public.trip_participants tp
    join public.trips t on t.id = tp.trip_id
    join public.profiles pr on pr.id = t.owner_id
   where tp.user_id = auth.uid()
     and tp.status = 'accepted'
     and t.deleted_at is null
     and not private.is_blocked(auth.uid(), t.owner_id)
   order by t.started_at desc
   limit least(greatest(p_limit, 1), 200);
$$;

-- Уведомление об отметке: настройка «Отметки в поездках» ------------------------------------------

alter table public.profiles add column notify_trip_tags boolean not null default true;
grant update (notify_trip_tags) on table public.profiles to authenticated;

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
      else true
    end
      from public.profiles p
     where p.id = p_user
  ), false);
$$;

-- Личные рекорды ---------------------------------------------------------------------------------

-- По каждому виду (кроме «другой рыбы»): сколько поймано, самый тяжёлый и самый длинный улов. Рекорд
-- дают только записи с одной рыбой; при равенстве — более ранний. Место — если оно ещё видно владельцу.
create function public.my_records()
returns table (
  species_id text,
  total_count bigint,
  weight_g integer,
  weight_at timestamptz,
  weight_catch_id uuid,
  weight_place_name text,
  length_mm integer,
  length_at timestamptz,
  length_catch_id uuid,
  length_place_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  with mine as (
    select k.id, k.species_id, k.count, k.weight_g, k.length_mm, k.at,
           case when p.id is not null
                     and p.deleted_at is null
                     and private.can_view(auth.uid(), p.owner_id, p.visibility)
                then p.name end as place_name
      from public.catches k
      left join public.places p on p.id = k.place_id
     where k.owner_id = auth.uid()
       and k.deleted_at is null
       and k.species_id <> 'other'
  ),
  totals as (
    select m.species_id, sum(m.count)::bigint as total
      from mine m
     group by m.species_id
  ),
  heaviest as (
    select distinct on (m.species_id) m.species_id, m.weight_g, m.at, m.id, m.place_name
      from mine m
     where m.count = 1 and m.weight_g is not null
     order by m.species_id, m.weight_g desc, m.at
  ),
  longest as (
    select distinct on (m.species_id) m.species_id, m.length_mm, m.at, m.id, m.place_name
      from mine m
     where m.count = 1 and m.length_mm is not null
     order by m.species_id, m.length_mm desc, m.at
  )
  select t.species_id, t.total,
         h.weight_g, h.at, h.id, h.place_name,
         l.length_mm, l.at, l.id, l.place_name
    from totals t
    left join heaviest h on h.species_id = t.species_id
    left join longest l on l.species_id = t.species_id
   order by t.total desc, t.species_id;
$$;

-- Права -----------------------------------------------------------------------------------------

revoke execute on function
  public.tag_trip_friends(uuid, uuid[]),
  public.untag_trip_friend(uuid, uuid),
  public.respond_trip_tag(uuid, boolean),
  public.trip_participants(uuid),
  public.my_trip_invitations(),
  public.my_joined_trips(integer),
  public.my_records()
from public, anon;

grant execute on function
  public.tag_trip_friends(uuid, uuid[]),
  public.untag_trip_friend(uuid, uuid),
  public.respond_trip_tag(uuid, boolean),
  public.trip_participants(uuid),
  public.my_trip_invitations(),
  public.my_joined_trips(integer),
  public.my_records()
to authenticated;
