-- M14: фото мест редакции — с Wikimedia Commons, под свободными лицензиями (CC0, CC BY, CC BY-SA, PD).
--
-- Строки — из supabase/data/places/photos.csv (миграции …_editorial_photos.sql собирает photos.py);
-- сами файлы лежат на R2 рядом с картой: photos/places/<id>.jpg и <id>_thumb.jpg (workflow
-- Editorial photos). Путь «photos/…» приложение открывает напрямую, без подписи, как публичный файл.
-- Автор и лицензия показываются под фото — условие лицензий.

create table public.place_editorial_photos (
  id           uuid primary key,
  place_id     uuid not null references public.places (id) on delete cascade,
  position     smallint not null default 1 check (position between 1 and 20),
  commons_file text not null check (commons_file ~* '^File:.+\.(jpe?g|png)$'),
  author       text not null check (length(author) between 1 and 300),
  license      text not null check (length(license) between 1 and 60),
  license_url  text check (license_url ~ '^https?://'),
  width        integer not null check (width > 0),
  height       integer not null check (height > 0),
  created_at   timestamptz not null default now(),
  unique (place_id, commons_file)
);

create index place_editorial_photos_place on public.place_editorial_photos (place_id, position);

-- Клиенту напрямую — ничего: фото отдаёт RPC, когда место видно.
alter table public.place_editorial_photos enable row level security;
revoke all on public.place_editorial_photos from anon, authenticated;

-- Фото редакции в карточке места — по порядку; место должно быть видно зрителю.
create function public.place_editorial_photos(p_place uuid)
returns table (
  id uuid,
  path text,
  thumb_path text,
  width integer,
  height integer,
  author text,
  license text,
  license_url text,
  source_url text
)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id,
         'photos/places/' || e.id::text || '.jpg',
         'photos/places/' || e.id::text || '_thumb.jpg',
         e.width, e.height, e.author, e.license, e.license_url,
         'https://commons.wikimedia.org/wiki/' || replace(e.commons_file, ' ', '_')
    from public.place_editorial_photos e
    join public.places p on p.id = e.place_id
   where e.place_id = p_place
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = auth.uid())
     and private.can_view(auth.uid(), p.owner_id, p.visibility)
   order by e.position, e.id;
$$;

revoke execute on function public.place_editorial_photos(uuid) from public;
grant execute on function public.place_editorial_photos(uuid) to anon, authenticated;

-- Карточки мест в списках: обложка — первое фото редакции, если оно есть.
create or replace function private.place_items(
  p_viewer uuid,
  p_ids uuid[],
  p_lon double precision,
  p_lat double precision
)
returns table (ord integer, item public.place_item)
language sql stable
security definer
set search_path = ''
as $$
  select i.ord::integer,
         row(
           p.id, p.type, p.name,
           extensions.st_x(s.pt), extensions.st_y(s.pt),
           s.fuzzed,
           case when s.fuzzed then private.approx_radius_m() else 0 end,
           p.visibility,
           p.owner_id is not distinct from p_viewer,
           p.owner_id = private.editorial_id(),
           case when h.pt is null then null
                else round(extensions.st_distance(s.pt::extensions.geography,
                                                  h.pt::extensions.geography))::integer end,
           rv.rating_avg, rv.reviews_count,
           rp.reports_30d, rp.last_report_at,
           ph.photo_path,
           coalesce(fr.friends, '[]'::jsonb),
           exists (select 1 from public.saved_places sp
                    where sp.owner_id = p_viewer and sp.place_id = p.id)
         )::public.place_item
    from unnest(p_ids) with ordinality as i (id, ord)
    join public.places p on p.id = i.id
    cross join (select private.viewer_point(p_lon, p_lat) as pt) h
    cross join lateral (
      select (p.approximate and p.owner_id is distinct from p_viewer) as fuzzed
    ) f
    cross join lateral (
      select case when f.fuzzed then p.approx_center else p.geom end as pt, f.fuzzed
    ) s
    -- Отзывы бывают только у публичных мест; авторы, с которыми есть блокировка, не считаются.
    cross join lateral (
      select round(avg(r.rating), 1) as rating_avg, count(*)::integer as reviews_count
        from public.reviews r
       where r.place_id = p.id
         and r.deleted_at is null
         and p.visibility = 'public'
         and (p_viewer is null or not private.is_blocked(p_viewer, r.owner_id))
    ) rv
    cross join lateral (
      select (count(*) filter (where c.at > now() - interval '30 days'))::integer as reports_30d,
             max(c.at) as last_report_at
        from public.checkins c
       where c.place_id = p.id
         and c.deleted_at is null
         and private.can_view(p_viewer, c.owner_id, c.visibility)
    ) rp
    -- Обложка: первое фото редакции, иначе последнее видимое фото посетителей.
    cross join lateral (
      select coalesce(
        (select 'photos/places/' || e.id::text || '_thumb.jpg'
           from public.place_editorial_photos e
          where e.place_id = p.id
          order by e.position, e.id
          limit 1),
        (select m.owner_id::text || '/' || m.id::text || '_thumb.jpg'
           from public.media m
           join public.checkins c on c.id = m.checkin_id
          where c.place_id = p.id
            and c.deleted_at is null
            and m.deleted_at is null
            and private.media_visible(p_viewer, m.id)
          order by c.at desc, m.created_at desc, m.id
          limit 1)
      ) as photo_path
    ) ph
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'username', x.username,
               'display_name', x.display_name, 'avatar_path', x.avatar_path
             ) order by x.last_at desc) as friends
        from (
          select pr.id, pr.username, pr.display_name, pr.avatar_path, max(c.at) as last_at
            from public.checkins c
            join public.friendships fs on fs.user_id = p_viewer and fs.friend_id = c.owner_id
            join public.profiles pr on pr.id = c.owner_id
           where c.place_id = p.id
             and c.deleted_at is null
             and private.can_view(p_viewer, c.owner_id, c.visibility)
           group by pr.id
           order by max(c.at) desc
           limit 3
        ) x
    ) fr on true
   where p.deleted_at is null
     and (p.status = 'published' or p.owner_id = p_viewer)
     and private.can_view(p_viewer, p.owner_id, p.visibility);
$$;
