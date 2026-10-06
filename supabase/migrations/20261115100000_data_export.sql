-- Экспорт: GPX своей поездки и все свои данные (план: docs/02-plan/01-profile.md — «Экспорт GPX и
-- данных», 1.1; спецификация — docs/04-beta/M26-export.md).
--
-- Только своё: точки трека — только своей поездки (полностью, без обрезки начала и конца — это ваши
-- данные); архив — только строки, где вы автор. Чужие данные — только то, что о них уже видно в
-- приложении: username и имя друзей, «близких» и заблокированных.

-- Точки трека: [долгота, широта, высота, время в секундах Unix].
create function private.track_points_json(p_track extensions.geometry) returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_array(
           round(extensions.st_x(d.geom)::numeric, 6),
           round(extensions.st_y(d.geom)::numeric, 6),
           round(extensions.st_z(d.geom)::numeric, 1),
           extensions.st_m(d.geom)::bigint
         ) order by d.path), '[]'::jsonb)
    from extensions.st_dumppoints(p_track) d;
$$;

revoke execute on function private.track_points_json(extensions.geometry) from public, anon, authenticated;

-- Точки своей поездки (для GPX). Чужая или удалённая — 42501 / P0002.
create function public.my_trip_points(p_trip uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  t public.trips;
begin
  if auth.uid() is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  select * into t from public.trips where id = p_trip and deleted_at is null;
  if t.id is null then
    raise exception 'trip not found' using errcode = 'P0002';
  end if;
  if t.owner_id <> auth.uid() then
    raise exception 'not yours' using errcode = '42501';
  end if;
  return case when t.track is null then '[]'::jsonb else private.track_points_json(t.track) end;
end;
$$;

-- Точка геометрии: [долгота, широта] или null.
create function private.point_json(p_geom extensions.geometry) returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_geom is null then null else jsonb_build_array(
    round(extensions.st_x(p_geom)::numeric, 6), round(extensions.st_y(p_geom)::numeric, 6)
  ) end;
$$;

revoke execute on function private.point_json(extensions.geometry) from public, anon, authenticated;

-- Все свои данные одним JSON. Удалённое не попадает.
create function public.export_my_data() returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  return jsonb_build_object(
    'format', 'dalada-export',
    'version', 1,
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = me),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'display_name', p.display_name, 'since', f.created_at)
               order by f.created_at)
        from public.friendships f join public.profiles p on p.id = f.friend_id
       where f.user_id = me), '[]'::jsonb),
    'close_friends', coalesce((
      select jsonb_agg(p.username order by p.username)
        from public.close_friends c join public.profiles p on p.id = c.friend_id
       where c.owner_id = me), '[]'::jsonb),
    'blocked', coalesce((
      select jsonb_agg(p.username order by p.username)
        from public.blocks b join public.profiles p on p.id = b.blocked_id
       where b.blocker_id = me), '[]'::jsonb),
    'places', coalesce((
      select jsonb_agg(
               (to_jsonb(p) - 'owner_id' - 'geom' - 'access_point' - 'approx_center' - 'deleted_at')
               || jsonb_build_object('point', private.point_json(p.geom), 'access_point', private.point_json(p.access_point))
               order by p.created_at)
        from public.places p
       where p.owner_id = me and p.deleted_at is null), '[]'::jsonb),
    'saved_places', coalesce((
      select jsonb_agg(jsonb_build_object('place_id', s.place_id, 'name', p.name, 'saved_at', s.created_at)
               order by s.created_at)
        from public.saved_places s join public.places p on p.id = s.place_id
       where s.owner_id = me), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(
               (to_jsonb(c) - 'owner_id' - 'geom' - 'deleted_at')
               || jsonb_build_object('point', private.point_json(c.geom), 'place_name', p.name)
               order by c.at)
        from public.checkins c join public.places p on p.id = c.place_id
       where c.owner_id = me and c.deleted_at is null), '[]'::jsonb),
    'catches', coalesce((
      select jsonb_agg(to_jsonb(k) - 'owner_id' - 'deleted_at' order by k.at)
        from public.catches k
       where k.owner_id = me and k.deleted_at is null), '[]'::jsonb),
    'trips', coalesce((
      select jsonb_agg(
               (to_jsonb(t) - 'owner_id' - 'track' - 'deleted_at')
               || jsonb_build_object('track', case when t.track is null then '[]'::jsonb else private.track_points_json(t.track) end)
               order by t.started_at)
        from public.trips t
       where t.owner_id = me and t.deleted_at is null), '[]'::jsonb),
    'trip_invitations', coalesce((
      select jsonb_agg(jsonb_build_object('trip_id', tp.trip_id, 'status', tp.status, 'invited_at', tp.created_at)
               order by tp.created_at)
        from public.trip_participants tp
       where tp.user_id = me), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg((to_jsonb(r) - 'owner_id' - 'deleted_at') || jsonb_build_object('place_name', p.name)
               order by r.created_at)
        from public.reviews r join public.places p on p.id = r.place_id
       where r.owner_id = me and r.deleted_at is null), '[]'::jsonb),
    'discussions', coalesce((
      select jsonb_agg(to_jsonb(t) - 'owner_id' - 'deleted_at' order by t.created_at)
        from public.threads t
       where t.owner_id = me and t.deleted_at is null), '[]'::jsonb),
    'discussion_replies', coalesce((
      select jsonb_agg(to_jsonb(tp) - 'owner_id' - 'deleted_at' order by tp.created_at)
        from public.thread_posts tp
       where tp.owner_id = me and tp.deleted_at is null), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(to_jsonb(c) - 'owner_id' - 'deleted_at' order by c.created_at)
        from public.comments c
       where c.owner_id = me and c.deleted_at is null), '[]'::jsonb),
    'reactions', coalesce((
      select jsonb_agg(to_jsonb(r) - 'owner_id' order by r.created_at)
        from public.reactions r
       where r.owner_id = me), '[]'::jsonb),
    'photos', coalesce((
      select jsonb_agg(to_jsonb(m) - 'owner_id' - 'deleted_at' order by m.created_at)
        from public.media m
       where m.owner_id = me and m.deleted_at is null), '[]'::jsonb),
    'gear', coalesce((
      select jsonb_agg(to_jsonb(g) - 'owner_id' - 'deleted_at' - 'synced_at' order by g.created_at)
        from public.gear_items g
       where g.owner_id = me and g.deleted_at is null), '[]'::jsonb),
    'checklists', coalesce((
      select jsonb_agg(to_jsonb(c) - 'owner_id' - 'deleted_at' - 'synced_at' order by c.created_at)
        from public.checklists c
       where c.owner_id = me and c.deleted_at is null), '[]'::jsonb),
    'privacy_zones', coalesce((
      select jsonb_agg(jsonb_build_object('name', z.name, 'center', private.point_json(z.geom), 'radius_m', z.radius_m,
                                          'created_at', z.created_at)
               order by z.created_at)
        from public.privacy_zones z
       where z.owner_id = me), '[]'::jsonb),
    'achievements', coalesce((
      select jsonb_agg(jsonb_build_object('achievement', a.achievement, 'earned_at', a.earned_at) order by a.earned_at)
        from public.achievements a
       where a.owner_id = me), '[]'::jsonb),
    'place_suggestions', coalesce((
      select jsonb_agg(to_jsonb(s) - 'author_id' order by s.created_at)
        from public.place_suggestions s
       where s.author_id = me), '[]'::jsonb),
    'complaints', coalesce((
      select jsonb_agg(jsonb_build_object('target_kind', r.target_kind, 'reason', r.reason, 'note', r.note,
                                          'status', r.status, 'created_at', r.created_at)
               order by r.created_at)
        from public.reports r
       where r.reporter_id = me), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.my_trip_points(uuid), public.export_my_data() from public, anon;
grant execute on function public.my_trip_points(uuid), public.export_my_data() to authenticated;
