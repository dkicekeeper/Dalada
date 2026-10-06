-- Закрытый профиль (план: docs/02-plan/01-profile.md — «Закрытый профиль (1.1): не друзьям видна только
-- шапка»; спецификация — docs/04-beta/M25-private-profile.md).
--
-- Кто не в друзьях, видит на странице человека только шапку: фото, имя, @username, город и кнопку
-- «Добавить в друзья». Поездки, места и итоги на странице — только друзьям. Видимость самих записей
-- не меняется: публичный отчёт по-прежнему виден в карточке места — закрывается именно страница.

alter table public.profiles add column is_private boolean not null default false;
grant update (is_private) on table public.profiles to authenticated;

-- Страница человека закрыта для зрителя: профиль закрыт, а зритель — не он сам и не друг.
create function private.profile_closed(p_owner uuid, p_viewer uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p.is_private from public.profiles p where p.id = p_owner), false)
     and p_viewer is distinct from p_owner
     and not private.are_friends(p_owner, p_viewer);
$$;

revoke execute on function private.profile_closed(uuid, uuid) from public, anon, authenticated;

-- Шапка профиля — с признаком «закрыт» (форма ответа меняется — пересоздаём).
drop function public.profile_by_username(text);

create function public.profile_by_username(p_username text)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_path text,
  city text,
  is_friend boolean,
  request_status text,
  is_private boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name, p.avatar_path, p.city,
         private.are_friends(auth.uid(), p.id),
         (select case when r.from_user = auth.uid() then 'outgoing' else 'incoming' end
            from public.friend_requests r
           where r.status = 'pending'
             and ((r.from_user = auth.uid() and r.to_user = p.id)
               or (r.from_user = p.id and r.to_user = auth.uid()))
           limit 1),
         p.is_private
    from public.profiles p
   where p.username = lower(p_username)
     and (auth.uid() is null or not private.is_blocked(auth.uid(), p.id));
$$;

revoke execute on function public.profile_by_username(text) from public, anon;
grant execute on function public.profile_by_username(text) to authenticated;

-- Поездки, места и итоги на странице — пусто, если страница закрыта.
create or replace function public.user_trips(p_user uuid, p_limit integer default 20, p_before timestamptz default null)
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
  visibility public.visibility
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.activity, t.title, t.note, t.started_at, t.ended_at,
         t.moving_seconds, t.distance_m, t.elevation_gain_m, t.max_speed_mps, t.visibility
    from public.trips t
   where t.owner_id = p_user
     and t.deleted_at is null
     and (p_before is null or t.started_at < p_before)
     and private.can_view(auth.uid(), t.owner_id, t.visibility)
     and not private.profile_closed(p_user, auth.uid())
   order by t.started_at desc
   limit least(greatest(p_limit, 1), 100);
$$;

create or replace function public.user_places(p_user uuid, p_limit integer default 100)
returns table (
  id uuid,
  owner_id uuid,
  type public.place_type,
  name text,
  lon double precision,
  lat double precision,
  approximate boolean,
  radius_m integer,
  visibility public.visibility,
  status public.place_status,
  is_own boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.owner_id, p.type, p.name,
         extensions.st_x(case when f.fuzzed then p.approx_center else p.geom end),
         extensions.st_y(case when f.fuzzed then p.approx_center else p.geom end),
         f.fuzzed,
         case when f.fuzzed then private.approx_radius_m() else 0 end,
         p.visibility, p.status,
         p.owner_id = auth.uid()
    from public.places p
    cross join lateral (
      select (p.approximate and p.owner_id is distinct from auth.uid()) as fuzzed
    ) f
   where p.owner_id = p_user
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = auth.uid())
     and private.can_view(auth.uid(), p.owner_id, p.visibility)
     and not private.profile_closed(p_user, auth.uid())
   order by p.created_at desc
   limit least(greatest(p_limit, 1), 200);
$$;

create or replace function public.user_stats(p_user uuid)
returns table (
  trips_count integer,
  distance_m bigint,
  places_count integer,
  catches_count bigint,
  friends_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*) from public.trips t
      where t.owner_id = p_user and t.deleted_at is null
        and private.can_view(auth.uid(), t.owner_id, t.visibility))::integer,
    (select coalesce(sum(t.distance_m), 0) from public.trips t
      where t.owner_id = p_user and t.deleted_at is null
        and private.can_view(auth.uid(), t.owner_id, t.visibility))::bigint,
    (select count(*) from public.places p
      where p.owner_id = p_user and p.deleted_at is null
        and (p.status = 'published' or p.owner_id = auth.uid())
        and private.can_view(auth.uid(), p.owner_id, p.visibility))::integer,
    (select coalesce(sum(k.count), 0) from public.catches k
      where k.owner_id = p_user and k.deleted_at is null
        and private.can_view(auth.uid(), k.owner_id, k.visibility))::bigint,
    (select count(*) from public.friendships f where f.user_id = p_user)::integer
   where auth.uid() is not null
     and not private.is_blocked(auth.uid(), p_user)
     and not private.profile_closed(p_user, auth.uid())
     and exists (select 1 from public.profiles where id = p_user);
$$;
