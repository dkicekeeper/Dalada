-- M15: участники поездки. A — автор, F и G — друзья A (у G выключены «Отметки в поездках»),
-- H — друг A, не отмеченный, S — чужой, K — друг A, которого A потом заблокирует.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(39);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.pushes(p_user uuid) returns integer language sql as $$
  select count(*)::integer from private.push_outbox where user_id = p_user and kind = 'trip_tag';
$$;

-- Трек из n точек на восток от (lon0, lat).
create function pg_temp.track(lon0 double precision, lat double precision, n integer)
returns extensions.geometry language sql as $$
  select extensions.st_setsrid(
    extensions.st_makeline(array_agg(
      extensions.st_makepoint(lon0 + i * 0.001, lat, 700, 1790485200 + i * 60) order by i)),
    4326)
    from generate_series(0, n - 1) i;
$$;

-- Видимый трек как геометрия (из GeoJSON ответа trip_view).
create function pg_temp.geo(track jsonb) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_geomfromgeojson(track::text), 4326)::extensions.geography;
$$;

create function pg_temp.pt(lon double precision, lat double precision) returns extensions.geography
language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(lon, lat), 4326)::extensions.geography;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('55555555-5555-5555-5555-555555555555', 'g@test.local'),
  ('66666666-6666-6666-6666-666666666666', 'h@test.local'),
  ('77777777-7777-7777-7777-777777777777', 'k@test.local');
update public.profiles set username = 'author' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'friend_f' where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set username = 'friend_g', notify_trip_tags = false where id = '55555555-5555-5555-5555-555555555555';

insert into public.friendships (user_id, friend_id)
select a, b from (values
  ('11111111-1111-1111-1111-111111111111'::uuid, '22222222-2222-2222-2222-222222222222'::uuid),
  ('11111111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555'),
  ('11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666'),
  ('11111111-1111-1111-1111-111111111111', '77777777-7777-7777-7777-777777777777')
) p(a, b)
union all
select b, a from (values
  ('11111111-1111-1111-1111-111111111111'::uuid, '22222222-2222-2222-2222-222222222222'::uuid),
  ('11111111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555'),
  ('11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666'),
  ('11111111-1111-1111-1111-111111111111', '77777777-7777-7777-7777-777777777777')
) p(a, b);

insert into public.devices (user_id, token, environment) values
  ('22222222-2222-2222-2222-222222222222', repeat('f2', 32), 'production'),
  ('55555555-5555-5555-5555-555555555555', repeat('a5', 32), 'production');

-- Поездка A «только для меня» и место с чекином для друзей во время поездки.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, title, started_at, ended_at, track, visibility) values
  ('99999999-0000-0000-0000-000000000001', 'Рыбалка втроём', now() - interval '1 day' - interval '100 minutes',
   now() - interval '1 day', pg_temp.track(77.000, 43.500, 101), 'private');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Место для друзей', 'SRID=4326;POINT(77.05 43.50)', 'friends');
insert into public.checkins (id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() - interval '1 day' - interval '50 minutes', 'friends');

-- Отметить ---------------------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ select public.tag_trip_friends('99999999-0000-0000-0000-000000000001',
       array['33333333-3333-3333-3333-333333333333']::uuid[]) $$,
  'P0002', null,
  'отмечать можно только в своей поездке'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  public.tag_trip_friends('99999999-0000-0000-0000-000000000001', array[
    '22222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555',
    '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222', null]::uuid[]),
  2,
  'отмечены только друзья: чужой, сам автор, повтор и пустое пропущены'
);
select is(
  (select count(*)::integer from public.trip_participants('99999999-0000-0000-0000-000000000001') where status = 'pending'),
  2,
  'автор видит обоих отмеченных как ждущих ответа'
);
select throws_ok(
  $$ select * from public.trip_participants $$,
  '42501', null,
  'таблица участников клиенту закрыта'
);

select pg_temp.act_as_admin();
select is(pg_temp.pushes('22222222-2222-2222-2222-222222222222'), 1, 'F получил уведомление об отметке');
select is(
  (select payload ->> 'target_id' from private.push_outbox
    where user_id = '22222222-2222-2222-2222-222222222222' and kind = 'trip_tag'),
  '99999999-0000-0000-0000-000000000001',
  'в уведомлении — поездка'
);
select is(pg_temp.pushes('55555555-5555-5555-5555-555555555555'), 0, 'G выключил «Отметки в поездках» — без уведомления');

-- Отмеченный, пока не ответил --------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*)::integer from public.trip_view('99999999-0000-0000-0000-000000000001')),
  1,
  'ждущий ответа видит поездку «только для меня»'
);
select is(
  (select is_own from public.trip_view('99999999-0000-0000-0000-000000000001')),
  false,
  'поездка для него чужая'
);
select ok(
  (select extensions.st_distance(pg_temp.geo(track), pg_temp.pt(77.000, 43.500)) > 150
     from public.trip_view('99999999-0000-0000-0000-000000000001')),
  'трек — как всем, кроме автора: без начала'
);
select is(
  (select count(*)::integer from public.trip_checkins('99999999-0000-0000-0000-000000000001')),
  1,
  'чекин автора для друзей виден участнику'
);
select is(
  (select title from public.my_trip_invitations()),
  'Рыбалка втроём',
  'приглашение — в «моих приглашениях»'
);
select is(
  (select string_agg(username || ':' || status || ':' || is_me, ',')
     from public.trip_participants('99999999-0000-0000-0000-000000000001')),
  'friend_f:pending:true',
  'ждущий видит только себя, другого ждущего — нет'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select count(*)::integer from public.trip_view('99999999-0000-0000-0000-000000000001')),
  0,
  'чужой поездку «только для меня» не видит'
);
select is(
  (select count(*)::integer from public.trip_participants('99999999-0000-0000-0000-000000000001')),
  0,
  'и участников не видит'
);

-- Принять ----------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ select public.respond_trip_tag('99999999-0000-0000-0000-000000000001', true) $$,
  'F принимает отметку'
);
select is(
  (select host_username || ':' || title from public.my_joined_trips()),
  'author:Рыбалка втроём',
  'поездка — в «моих поездках» участника, с автором'
);
select is((select count(*)::integer from public.my_trip_invitations()), 0, 'приглашений больше нет');
select throws_ok(
  $$ select public.respond_trip_tag('99999999-0000-0000-0000-000000000001', true) $$,
  'P0002', null,
  'принять второй раз нельзя'
);

select pg_temp.act_as_admin();
select ok(private.reaction_target_visible('22222222-2222-2222-2222-222222222222', 'trip', '99999999-0000-0000-0000-000000000001'),
  'участник может ставить реакции и комментировать');
select ok(not private.reaction_target_visible('33333333-3333-3333-3333-333333333333', 'trip', '99999999-0000-0000-0000-000000000001'),
  'чужой — нет');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  public.tag_trip_friends('99999999-0000-0000-0000-000000000001', array['22222222-2222-2222-2222-222222222222']::uuid[]),
  0,
  'повторная отметка принявшего ничего не меняет'
);
select pg_temp.act_as_admin();
select is(pg_temp.pushes('22222222-2222-2222-2222-222222222222'), 1, 'и второго уведомления нет');

-- Другие зрители видят только принявших ---------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.trips set visibility = 'friends' where id = '99999999-0000-0000-0000-000000000001';
select pg_temp.act_as('66666666-6666-6666-6666-666666666666');
select is(
  (select string_agg(username, ',') from public.trip_participants('99999999-0000-0000-0000-000000000001')),
  'friend_f',
  'друг автора видит принявшего, но не ждущего ответа'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.trips set visibility = 'private' where id = '99999999-0000-0000-0000-000000000001';

-- Чужой не убирает отметки -----------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.untag_trip_friend('99999999-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555');
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*)::integer from public.trip_participants('99999999-0000-0000-0000-000000000001')),
  2,
  'участник не может убрать чужую отметку'
);

-- Выйти и не вернуться ---------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ select public.respond_trip_tag('99999999-0000-0000-0000-000000000001', false) $$,
  'F выходит из поездки'
);
select is(
  (select count(*)::integer from public.trip_view('99999999-0000-0000-0000-000000000001')),
  0,
  'вышедший больше не видит поездку «только для меня»'
);
select is((select count(*)::integer from public.my_joined_trips()), 0, 'и её нет в его поездках');
select throws_ok(
  $$ select public.respond_trip_tag('99999999-0000-0000-0000-000000000001', true) $$,
  'P0002', null,
  'вышедший не может принять отметку снова'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  public.tag_trip_friends('99999999-0000-0000-0000-000000000001', array['22222222-2222-2222-2222-222222222222']::uuid[]),
  0,
  'вышедшего нельзя отметить снова'
);
select is(
  (select string_agg(username, ',') from public.trip_participants('99999999-0000-0000-0000-000000000001')),
  'friend_g',
  'отклонивший автору не показывается'
);

-- Автор убирает отметку --------------------------------------------------------------------------

select public.untag_trip_friend('99999999-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555');
select is(
  (select count(*)::integer from public.trip_participants('99999999-0000-0000-0000-000000000001')),
  0,
  'автор убрал отметку'
);
select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select is(
  (select count(*)::integer from public.trip_view('99999999-0000-0000-0000-000000000001')),
  0,
  'и поездка снятому с отметки больше не видна'
);

-- Блокировка закрывает отметку ---------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.tag_trip_friends('99999999-0000-0000-0000-000000000001', array['77777777-7777-7777-7777-777777777777']::uuid[]);
insert into public.blocks (blocked_id) values ('77777777-7777-7777-7777-777777777777');
select pg_temp.act_as('77777777-7777-7777-7777-777777777777');
select is(
  (select count(*)::integer from public.trip_view('99999999-0000-0000-0000-000000000001')),
  0,
  'заблокированный автором участник поездку не видит'
);
select is((select count(*)::integer from public.my_trip_invitations()), 0, 'и приглашения у него нет');

-- Не больше 20 отметок -----------------------------------------------------------------------------

select pg_temp.act_as_admin();
insert into auth.users (id, email)
select ('dddddddd-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'many' || i || '@test.local'
  from generate_series(1, 21) i;
insert into public.friendships (user_id, friend_id)
select '11111111-1111-1111-1111-111111111111', ('dddddddd-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid
  from generate_series(1, 21) i
union all
select ('dddddddd-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, '11111111-1111-1111-1111-111111111111'
  from generate_series(1, 21) i;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, title, started_at, ended_at, visibility) values
  ('99999999-0000-0000-0000-000000000002', 'Большая компания', now() - interval '2 hours', now() - interval '1 hour', 'friends');
select throws_ok(
  $$ select public.tag_trip_friends('99999999-0000-0000-0000-000000000002',
       (select array_agg(('dddddddd-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid) from generate_series(1, 21) i)) $$,
  '54000', null,
  'больше 20 отметок на поездку нельзя'
);
select is(
  public.tag_trip_friends('99999999-0000-0000-0000-000000000002',
    (select array_agg(('dddddddd-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid) from generate_series(1, 20) i)),
  20,
  'двадцать — можно'
);

-- Удалённая поездка --------------------------------------------------------------------------------

select pg_temp.act_as('dddddddd-0000-0000-0000-000000000001');
select public.respond_trip_tag('99999999-0000-0000-0000-000000000002', true);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.trips set deleted_at = now() where id = '99999999-0000-0000-0000-000000000002';
select pg_temp.act_as('dddddddd-0000-0000-0000-000000000001');
select is((select count(*)::integer from public.my_joined_trips()), 0, 'удалённой поездки у участника нет');

-- Гость ------------------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select throws_ok(
  $$ select * from public.trip_participants('99999999-0000-0000-0000-000000000001') $$,
  '42501', null,
  'гостю участники недоступны'
);

select * from finish();
rollback;
