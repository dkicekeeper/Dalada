-- Слой «Мои треки» на карте (план: docs/02-plan/02-map.md, «Слои»): треки своих поездок поверх
-- карты. Только свои, только не удалённые; трек упрощён (≈10 м) и без высоты и времени — для
-- рисования этого хватает, а ответ маленький и хранится на телефоне.

create function public.my_tracks(p_limit integer default 300)
returns table (
  trip_id    uuid,
  activity   public.trip_activity,
  started_at timestamptz,
  track      jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.activity, t.started_at,
         extensions.st_asgeojson(extensions.st_simplify(extensions.st_force2d(t.track), 0.0001), 5)::jsonb
    from public.trips t
   where t.owner_id = auth.uid()
     and t.deleted_at is null
     and t.track is not null
   order by t.started_at desc
   limit least(greatest(coalesce(p_limit, 300), 1), 1000);
$$;

revoke execute on function public.my_tracks(integer) from public, anon;
grant execute on function public.my_tracks(integer) to authenticated;
