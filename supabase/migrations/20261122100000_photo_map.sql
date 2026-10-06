-- Слой карты «Мои фото» (план: docs/02-plan/01-profile.md — «Фото на карте», 1.1; спецификация —
-- docs/04-beta/M33-photo-map.md).
--
-- Только свои фото: точка — где был отчёт (своя точка, а не место), иначе — точка места, если оно ещё
-- видно владельцу. Свои данные — настоящие координаты. Фото без точки (место удалено) — не на карте.

create function public.my_photo_points(p_limit integer default 1000)
returns table (
  id uuid,
  path text,
  thumb_path text,
  width integer,
  height integer,
  created_at timestamptz,
  checkin_id uuid,
  catch_id uuid,
  review_id uuid,
  place_id uuid,
  place_name text,
  lon double precision,
  lat double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.storage_path,
         m.owner_id::text || '/' || m.id::text || '_thumb.jpg',
         m.width, m.height, m.created_at,
         m.checkin_id, m.catch_id, m.review_id, m.place_id,
         case when visible.place then p.name end,
         extensions.st_x(coalesce(c.geom, case when visible.place then p.geom end)),
         extensions.st_y(coalesce(c.geom, case when visible.place then p.geom end))
    from public.media m
    left join public.checkins c on c.id = m.checkin_id and c.deleted_at is null
    left join public.places p on p.id = coalesce(m.place_id, c.place_id)
    cross join lateral (
      select p.id is not null and p.deleted_at is null
             and (p.owner_id = auth.uid()
                  or (p.status = 'published' and private.can_view(auth.uid(), p.owner_id, p.visibility))) as place
    ) visible
   where m.owner_id = auth.uid()
     and m.deleted_at is null
     and coalesce(c.geom, case when visible.place then p.geom end) is not null
   order by m.created_at desc
   limit least(greatest(coalesce(p_limit, 1000), 1), 2000);
$$;

revoke execute on function public.my_photo_points(integer) from public, anon;
grant execute on function public.my_photo_points(integer) to authenticated;
