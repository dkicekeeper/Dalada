-- Веб-страницы для «Поделиться» (план: docs/02-plan/05-cross-cutting.md, «Шаринг и рост» — «Лёгкая
-- веб-версия места, поездки, улова с превью в Telegram», 1.1; спецификация — docs/04-beta/M29-web-share.md).
--
-- Страницы на GitHub Pages читают данные ключом гостя. Отдаём только публичное — то, что и так видит
-- гость в приложении: трек поездки — как его видит гость (без начала и конца, зон приватности и
-- участков у закрытых мест), у улова — без скрытого размера, место — только публичное. Найти запись
-- можно только по ссылке (UUID); списка поездок и уловов нет.

-- Публичные опубликованные места — для статических страниц с превью (сборка сайта раз в день).
create function public.web_places()
returns table (
  id uuid,
  type public.place_type,
  name text,
  description text,
  lon double precision,
  lat double precision,
  approximate boolean,
  photo_path text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.type, p.name, p.description,
         extensions.st_x(case when p.approximate then p.approx_center else p.geom end),
         extensions.st_y(case when p.approximate then p.approx_center else p.geom end),
         p.approximate,
         (select 'photos/places/' || e.id::text || '.jpg'
            from public.place_editorial_photos e
           where e.place_id = p.id
           order by e.position, e.id
           limit 1),
         p.updated_at
    from public.places p
   where p.deleted_at is null
     and p.status = 'published'
     and p.visibility = 'public'
   order by p.id;
$$;

-- Публичная поездка для страницы: цифры, автор и трек как у гостя.
create function public.web_trip(p_trip uuid)
returns table (
  activity public.trip_activity,
  title text,
  started_at timestamptz,
  moving_seconds integer,
  distance_m integer,
  elevation_gain_m integer,
  author_username text,
  author_name text,
  track jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.activity, t.title, t.started_at, t.moving_seconds, t.distance_m, t.elevation_gain_m,
         pr.username, pr.display_name,
         extensions.st_asgeojson(
           extensions.st_simplify(extensions.st_force2d(private.visible_track(t, null)), 0.00005), 5
         )::jsonb
    from public.trips t
    join public.profiles pr on pr.id = t.owner_id
   where t.id = p_trip
     and t.deleted_at is null
     and t.visibility = 'public'
     and (auth.uid() is null or not private.is_blocked(auth.uid(), t.owner_id));
$$;

-- Публичный улов для страницы: вид, размер (если не скрыт), дата, фото, место — если публичное.
create function public.web_catch(p_catch uuid)
returns table (
  species_id text,
  species_ru text,
  species_kk text,
  species_en text,
  weight_g integer,
  length_mm integer,
  count integer,
  released boolean,
  caught_on date,
  photo_path text,
  place_id uuid,
  place_name text,
  author_username text,
  author_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select k.species_id, s.name_ru, s.name_kk, s.name_en,
         case when k.hide_size then null else k.weight_g end,
         case when k.hide_size then null else k.length_mm end,
         k.count, k.released,
         (k.at at time zone 'Asia/Almaty')::date,
         (select m.storage_path
            from public.media m
           where m.catch_id = k.id and m.owner_id = k.owner_id and m.deleted_at is null
           order by m.created_at desc
           limit 1),
         case when private.is_open_place(k.place_id, null) then k.place_id end,
         case when private.is_open_place(k.place_id, null) then p.name end,
         pr.username, pr.display_name
    from public.catches k
    join public.profiles pr on pr.id = k.owner_id
    left join public.fish_species s on s.id = k.species_id
    left join public.places p on p.id = k.place_id
   where k.id = p_catch
     and k.deleted_at is null
     and k.visibility = 'public'
     and (auth.uid() is null or not private.is_blocked(auth.uid(), k.owner_id));
$$;

revoke execute on function public.web_places(), public.web_trip(uuid), public.web_catch(uuid) from public;
grant execute on function public.web_places(), public.web_trip(uuid), public.web_catch(uuid)
  to anon, authenticated;
