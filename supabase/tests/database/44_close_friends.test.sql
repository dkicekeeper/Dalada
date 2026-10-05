-- Видимость «Близкие»: видят только друзья из списка автора; список закрыт и только из друзей;
-- отчёт в месте «Близкие» не видимее места; пуш о новом отчёте — только близким; разрыв дружбы
-- убирает из списка. A — автор, B — близкий друг, C — просто друг, D — не друг.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

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

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local');

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111');
insert into public.devices (user_id, token, environment) values
  ('22222222-2222-2222-2222-222222222222', repeat('b2', 32), 'production'),
  ('33333333-3333-3333-3333-333333333333', repeat('c3', 32), 'production');

-- Список ------------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ insert into public.close_friends (friend_id) values ('44444444-4444-4444-4444-444444444444') $$,
  '22023', null,
  'не друга — нельзя'
);
select lives_ok(
  $$ insert into public.close_friends (friend_id) values ('22222222-2222-2222-2222-222222222222') $$,
  'друга — можно'
);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.close_friends), 0, 'чужой список не виден — и самому близкому');

-- Видимость ---------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Общее', 'SRID=4326;POINT(77.00 43.90)', 'friends'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Для близких', 'SRID=4326;POINT(77.10 43.90)', 'close_friends');
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'close_friends');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')), 1, 'близкий видит отчёт «Близкие»');
select ok(
  exists (select 1 from public.places_in_bbox(76.5, 43.5, 77.5, 44.3) where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'и место «Близкие»'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::integer from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')), 0, 'просто друг — нет');
select ok(
  not exists (select 1 from public.places_in_bbox(76.5, 43.5, 77.5, 44.3) where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'и места не видит'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::integer from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')), 0, 'не друг — нет');

select pg_temp.act_as_anon();
select ok(
  not exists (select 1 from public.places_in_bbox(76.5, 43.5, 77.5, 44.3) where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'гость — нет'
);

-- Не видимее места --------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'friends');
select is(
  (select visibility from public.checkins where id = 'cccccccc-0000-0000-0000-000000000002'),
  'close_friends'::public.visibility,
  'отчёт «друзья» в месте «Близкие» — «Близкие»'
);
update public.checkins set visibility = 'public' where id = 'cccccccc-0000-0000-0000-000000000002';
select is(
  (select visibility from public.checkins where id = 'cccccccc-0000-0000-0000-000000000002'),
  'close_friends'::public.visibility,
  'и при правке'
);
insert into public.catches (id, checkin_id, species_id, visibility) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000002', 'pike', 'public');
select is(
  (select visibility from public.catches where id = 'dddddddd-0000-0000-0000-000000000001'),
  'close_friends'::public.visibility,
  'улов — тоже'
);
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000002', 'private');
select is(
  (select visibility from public.checkins where id = 'cccccccc-0000-0000-0000-000000000003'),
  'private'::public.visibility,
  '«только я» остаётся'
);

-- Пуш о новом отчёте ------------------------------------------------------------------------------

select pg_temp.act_as_admin();
select is(
  (select count(*)::integer from private.push_outbox
    where kind = 'friend_post' and user_id = '22222222-2222-2222-2222-222222222222'),
  1,
  'близкому — пуш о новом отчёте'
);
select is(
  (select count(*)::integer from private.push_outbox
    where kind = 'friend_post' and user_id = '33333333-3333-3333-3333-333333333333'),
  0,
  'просто другу — нет'
);

-- Разрыв дружбы -----------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('22222222-2222-2222-2222-222222222222');
select pg_temp.act_as_admin();
select is((select count(*)::integer from public.close_friends), 0, 'блокировка (разрыв дружбы) убирает из списка');
delete from public.blocks;
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')), 0, 'снова друзья — но уже не близкий');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select count(*)::integer from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')), 1, 'автор видит своё всегда');

select * from finish();
rollback;
