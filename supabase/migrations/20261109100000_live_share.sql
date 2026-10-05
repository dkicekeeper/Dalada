-- Трансляция геопозиции друзьям во время поездки (план: docs/02-plan/README.md, релиз 1.1 —
-- «трансляция геопозиции друзьям»; спецификация — docs/04-beta/M20-live-location.md).
--
-- Пока идёт запись поездки, автор может показывать, где он, выбранным друзьям: телефон присылает
-- точку раз в несколько минут, друзья видят последнюю точку и её время. Хранится одна последняя
-- точка, без истории. Трансляция кончается, когда автор её выключит или закончит поездку, и сама —
-- через p_hours (1–24, по умолчанию 12).
--
-- Кто видит: только выбранные друзья (не больше 50), пока они друзья и никто никого не заблокировал.
-- Точка внутри зоны приватности автора не отдаётся — как и трек. Таблицы клиенту закрыты: всё через
-- функции ниже.

create table public.live_shares (
  owner_id    uuid primary key references public.profiles (id) on delete cascade,
  geom        extensions.geometry(Point, 4326),
  accuracy_m  real check (accuracy_m is null or accuracy_m between 0 and 10000),
  started_at  timestamptz not null default now(),
  -- Время последней точки.
  updated_at  timestamptz,
  expires_at  timestamptz not null
);

create table public.live_share_viewers (
  owner_id  uuid not null references public.live_shares (owner_id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  primary key (owner_id, viewer_id)
);

create index live_share_viewers_viewer_idx on public.live_share_viewers (viewer_id);

alter table public.live_shares enable row level security;
alter table public.live_share_viewers enable row level security;
revoke all on table public.live_shares, public.live_share_viewers from anon, authenticated;

create function private.live_share_viewers_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 50 $$;

-- Начать трансляцию (или перезапустить с другим списком): зрители — друзья из p_viewers, остальные
-- отбрасываются; если друзей среди них нет — 22023. Возвращает, до какого времени она идёт.
create function public.start_live_share(p_viewers uuid[], p_hours integer default 12)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  until timestamptz := now() + make_interval(hours => least(greatest(coalesce(p_hours, 12), 1), 24));
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_viewers), 0) > private.live_share_viewers_limit() then
    raise exception 'too many viewers' using errcode = '54000';
  end if;

  insert into public.live_shares (owner_id, started_at, expires_at)
  values (me, now(), until)
  on conflict (owner_id) do update
    set started_at = now(), expires_at = excluded.expires_at, geom = null, accuracy_m = null, updated_at = null;

  delete from public.live_share_viewers where owner_id = me;
  insert into public.live_share_viewers (owner_id, viewer_id)
  select distinct me, v
    from unnest(p_viewers) as v
   where v <> me
     and private.are_friends(me, v)
     and not private.is_blocked(me, v);
  if not found then
    delete from public.live_shares where owner_id = me;
    raise exception 'no friends among viewers' using errcode = '22023';
  end if;
  return until;
end;
$$;

-- Новая точка. false — трансляции нет или она кончилась: телефону пора перестать присылать.
create function public.update_live_location(
  p_lon double precision,
  p_lat double precision,
  p_accuracy real default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'invalid point' using errcode = '22023';
  end if;
  update public.live_shares
     set geom = extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326),
         accuracy_m = case when p_accuracy between 0 and 10000 then p_accuracy end,
         updated_at = now()
   where owner_id = auth.uid()
     and expires_at > now();
  return found;
end;
$$;

-- Выключить трансляцию: точка и список зрителей удаляются.
create function public.stop_live_share()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.live_shares where owner_id = auth.uid();
$$;

-- Своя трансляция: идёт ли, до какого времени, когда была последняя точка и кому видна.
create function public.my_live_share()
returns table (
  started_at timestamptz,
  expires_at timestamptz,
  updated_at timestamptz,
  viewer_ids uuid[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.started_at, s.expires_at, s.updated_at,
         coalesce(array_agg(v.viewer_id order by v.viewer_id) filter (where v.viewer_id is not null), '{}')
    from public.live_shares s
    left join public.live_share_viewers v on v.owner_id = s.owner_id
   where s.owner_id = auth.uid()
     and s.expires_at > now()
   group by s.owner_id;
$$;

-- Кто из друзей сейчас показывает мне, где он: последняя точка (null — ещё нет или автор в своей зоне
-- приватности), её время и точность.
create function public.friends_live_locations()
returns table (
  owner_id uuid,
  username text,
  display_name text,
  avatar_path text,
  latitude double precision,
  longitude double precision,
  accuracy_m real,
  updated_at timestamptz,
  started_at timestamptz,
  expires_at timestamptz,
  in_privacy_zone boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.owner_id, p.username, p.display_name, p.avatar_path,
         case when h.hidden then null else extensions.st_y(s.geom) end,
         case when h.hidden then null else extensions.st_x(s.geom) end,
         case when h.hidden then null else s.accuracy_m end,
         s.updated_at, s.started_at, s.expires_at, h.hidden
    from public.live_shares s
    join public.live_share_viewers v on v.owner_id = s.owner_id and v.viewer_id = auth.uid()
    join public.profiles p on p.id = s.owner_id
    cross join lateral (
      select s.geom is not null and exists (
        select 1
          from public.privacy_zones z
         where z.owner_id = s.owner_id
           and extensions.st_dwithin(
                 z.hidden_center::extensions.geography,
                 s.geom::extensions.geography,
                 private.zone_hidden_radius_m(z.radius_m)
               )
      ) as hidden
    ) h
   where s.expires_at > now()
     and private.are_friends(auth.uid(), s.owner_id)
     and not private.is_blocked(auth.uid(), s.owner_id)
   order by s.updated_at desc nulls last, s.owner_id;
$$;

revoke execute on function
  private.live_share_viewers_limit(),
  public.start_live_share(uuid[], integer),
  public.update_live_location(double precision, double precision, real),
  public.stop_live_share(),
  public.my_live_share(),
  public.friends_live_locations()
from public, anon;

grant execute on function
  public.start_live_share(uuid[], integer),
  public.update_live_location(double precision, double precision, real),
  public.stop_live_share(),
  public.my_live_share(),
  public.friends_live_locations()
to authenticated;

-- Кончившиеся трансляции — стереть через час после конца (точку не держим дольше нужного).
select cron.schedule(
  'live-shares-cleanup',
  '23 * * * *',
  $$delete from public.live_shares where expires_at < now() - interval '1 hour'$$
);
