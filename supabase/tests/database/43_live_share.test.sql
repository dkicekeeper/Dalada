-- Трансляция геопозиции: видят только выбранные друзья; в зоне приватности точки нет; после конца,
-- остановки, разрыва дружбы и блокировки — не видно; таблицы закрыты.
-- A — автор, B — друг (выбран), C — друг (не выбран), D — не друг.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(19);

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

-- Начало ----------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select public.start_live_share(array['44444444-4444-4444-4444-444444444444']::uuid[]) $$,
  '22023', null,
  'без друзей среди зрителей — нельзя'
);
select ok(
  public.start_live_share(array['22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444']::uuid[], 30)
    between now() + interval '23 hours 59 minutes' and now() + interval '24 hours',
  'до 24 часов, даже если просили больше'
);
select is(
  (select viewer_ids from public.my_live_share()),
  array['22222222-2222-2222-2222-222222222222']::uuid[],
  'в зрителях — только друг, не друг отброшен'
);
select throws_ok(
  $$ select public.update_live_location(200, 43.9) $$,
  '22023', null,
  'неверная точка'
);
select ok(public.update_live_location(77.05, 43.90, 12), 'точка принята');

-- Кто видит --------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select round(latitude::numeric, 2) || ',' || round(longitude::numeric, 2) from public.friends_live_locations()),
  '43.90,77.05',
  'выбранный друг видит точку'
);
select throws_ok(
  $$ select * from public.live_shares $$,
  '42501', null,
  'таблица закрыта'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::integer from public.friends_live_locations()), 0, 'невыбранный друг — нет');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::integer from public.friends_live_locations()), 0, 'не друг — нет');

select pg_temp.act_as_anon();
select throws_ok(
  $$ select * from public.friends_live_locations() $$,
  '42501', null,
  'гость — нет'
);

-- Зона приватности --------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.privacy_zones (name, geom, radius_m) values ('Дом', 'SRID=4326;POINT(77.05 43.90)', 500);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(
  (select latitude is null and longitude is null and in_privacy_zone from public.friends_live_locations()),
  'в зоне приватности автора точки нет'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(public.update_live_location(77.20, 43.95), 'уехал из зоны');
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(
  (select latitude is not null and not in_privacy_zone from public.friends_live_locations()),
  'вне зоны — снова видно'
);

-- Конец ------------------------------------------------------------------------------------------

-- Блокировка.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('22222222-2222-2222-2222-222222222222');
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.friends_live_locations()), 0, 'после блокировки — нет');
select pg_temp.act_as_admin();
delete from public.blocks;
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111')
on conflict do nothing;

-- Срок вышел.
update public.live_shares set expires_at = now() - interval '1 minute';
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.friends_live_locations()), 0, 'срок вышел — нет');
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(not public.update_live_location(77.0, 43.9), 'точку после конца не принимаем');
select is((select count(*)::integer from public.my_live_share()), 0, 'и своей трансляции уже нет');

-- Остановка.
select public.start_live_share(array['22222222-2222-2222-2222-222222222222']::uuid[]);
select public.stop_live_share();
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.friends_live_locations()), 0, 'остановил — нет');
select pg_temp.act_as_admin();
select is((select count(*)::integer from public.live_share_viewers), 0, 'список зрителей удалён');

select * from finish();
rollback;
