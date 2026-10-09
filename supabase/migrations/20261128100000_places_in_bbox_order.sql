-- M34: мест редакции по стране — больше 1400, и в широкой области карты их больше, чем помещается в
-- ответ (max_results, по умолчанию 500). Раньше порядок был случайным, и свои места могли не попасть
-- на карту. Теперь сначала свои, потом места людей, потом места редакции — в устойчивом
-- перемешанном порядке (по md5 id), чтобы при отдалении точки ложились по всей области, а не кучей.
create or replace function public.places_in_bbox(
  min_lon double precision,
  min_lat double precision,
  max_lon double precision,
  max_lat double precision,
  max_results integer default 500
)
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
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  editorial uuid := private.editorial_id();
  env extensions.geometry;
  -- Запас для индексного предфильтра: показанная точка отстоит от настоящей меньше чем на
  -- approx_radius_m (1 км ≈ 0.009° широты, ≈ 0.013° долготы на 45° с.ш.).
  margin constant double precision := 0.02;
begin
  if min_lon is null or min_lat is null or max_lon is null or max_lat is null
     or min_lon >= max_lon or min_lat >= max_lat
     or max_lon - min_lon > 10 or max_lat - min_lat > 10 then
    raise exception 'invalid bbox' using errcode = '22023';
  end if;

  env := extensions.st_makeenvelope(min_lon, min_lat, max_lon, max_lat, 4326);

  return query
  select p.id, p.owner_id, p.type, p.name,
         extensions.st_x(s.pt), extensions.st_y(s.pt),
         s.fuzzed,
         case when s.fuzzed then private.approx_radius_m() else 0 end,
         p.visibility, p.status,
         p.owner_id is not distinct from viewer
    from public.places p
    cross join lateral (
      select (p.approximate and p.owner_id is distinct from viewer) as fuzzed
    ) f
    cross join lateral (
      select case when f.fuzzed then p.approx_center else p.geom end as pt, f.fuzzed
    ) s
   where extensions.st_intersects(p.geom, extensions.st_expand(env, margin))
     and extensions.st_intersects(s.pt, env)
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = viewer)
     and private.can_view(viewer, p.owner_id, p.visibility)
   order by p.owner_id is not distinct from viewer desc,
            p.owner_id = editorial,
            md5(p.id::text)
   limit least(greatest(max_results, 1), 1000);
end;
$$;
